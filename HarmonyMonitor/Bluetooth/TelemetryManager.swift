// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

@MainActor
@Observable
final class TelemetryManager {
    enum Status: Equatable {
        case offline, identifying, waiting, live, stale, unavailable(String), diagnostics(String)

        var message: String? {
            switch self {
            case .offline, .live: nil
            case .identifying: "Checking the selected device’s firmware identity."
            case .waiting: "Waiting for the first BMS telemetry reply."
            case .stale: "The last successful update has expired."
            case .unavailable(let reason), .diagnostics(let reason): reason
            }
        }
    }

    enum RefreshRate: Int, CaseIterable, Identifiable {
        case one = 1
        case two = 2
        case five = 5

        var id: Int { rawValue }
        var label: String { "\(rawValue) s" }
    }

    enum TemperatureUnit: String, CaseIterable, Identifiable {
        case celsius = "°C"
        case fahrenheit = "°F"

        var id: String { rawValue }

        func reading(_ celsius: Double?) -> String {
            guard let celsius else { return "—" }
            let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
            return "\(value.formatted(.number.precision(.fractionLength(1)))) \(rawValue)"
        }
    }

    struct LogEntry: Identifiable {
        let id: Int
        let time: Date
        let message: String
    }

    private struct PendingRequest {
        let command: VESCRequest
        let deadline: TimeInterval
    }

    let bluetooth: BLEManager
    private(set) var status: Status = .offline
    private(set) var telemetry: BMSDataModel?
    private(set) var firmware: FirmwareIdentity?
    private(set) var lastSuccessfulUpdate: Date?
    private(set) var logs: [LogEntry] = []
    var captureRawNotifications = false

    var refreshRate: RefreshRate {
        didSet { defaults.set(refreshRate.rawValue, forKey: "refreshRate") }
    }

    var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: "temperatureUnit") }
    }

    var autoReconnect: Bool {
        didSet {
            defaults.set(autoReconnect, forKey: "autoReconnect")
            bluetooth.setAutomaticReconnect(autoReconnect)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var decoder = VESCPacketCodec.Stream()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var pending: PendingRequest?
    @ObservationIgnored private var nextRequestAt: TimeInterval = 0
    @ObservationIgnored private var lastSampleAt: TimeInterval?
    @ObservationIgnored private var identityAttempts = 0
    @ObservationIgnored private var consecutiveMisses = 0
    @ObservationIgnored private var nextLogID = 0

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshRate = RefreshRate(rawValue: defaults.integer(forKey: "refreshRate")) ?? .one
        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        autoReconnect = defaults.object(forKey: "autoReconnect") as? Bool ?? true
        bluetooth = BLEManager()
        bluetooth.setAutomaticReconnect(autoReconnect)
        bluetooth.onEvent = { [weak self] event in self?.receive(event) }
    }

    func connect(_ device: BLEManager.Device, intent: BLEManager.Intent = .monitor) {
        lastSuccessfulUpdate = nil
        bluetooth.connect(device, intent: intent)
    }

    func setForeground(_ foreground: Bool) {
        bluetooth.setForeground(foreground)
        if foreground {
            guard timer == nil else { return }
            timer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard self != nil else { return }
                    self?.tick()
                    do { try await Task.sleep(for: .milliseconds(200)) }
                    catch { return }
                }
            }
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    func listenForDiagnostics(_ enabled: Bool, on characteristic: BLEManager.Characteristic) {
        if enabled { captureRawNotifications = true }
        bluetooth.setDiagnosticListening(enabled, for: characteristic.id)
    }

    func clearLogs() { logs.removeAll() }

    func exportLogs() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["Harmony Monitor diagnostics"]
        if let device = bluetooth.target { lines.append("Device: \(device.name) (\(device.id))") }
        if let firmware { lines.append("Firmware: \(firmware.hardwareName) \(firmware.versionLabel)") }
        lines += logs.map { "\(formatter.string(from: $0.time))  \($0.message)" }
        return lines.joined(separator: "\n")
    }

    private func receive(_ event: BLEManager.Event) {
        switch event {
        case .log(let message):
            log(message)
        case .ready:
            resetLinkState()
            status = .identifying
        case .ended:
            resetLinkState()
            status = .offline
        case .inspect(let reason):
            resetLinkState()
            status = .diagnostics(reason)
        case .notification(let uuid, let data, let isVESC):
            if captureRawNotifications {
                let hex = Self.hex(data)
                log("RX \(uuid) • \(data.count) bytes • \(hex)")
            }
            if isVESC, pending != nil {
                let batch = decoder.receive(data)
                consume(batch)
            }
        }
    }

    private func tick() {
        let now = uptime
        bluetooth.tick(now)
        guard bluetooth.phase == .ready else { return }
        if case .diagnostics = status { return }

        let refreshSeconds = Double(refreshRate.rawValue)
        let maxReadingAge = max(4, refreshSeconds * 3)
        if telemetry != nil, let lastSampleAt, now - lastSampleAt >= maxReadingAge {
            telemetry = nil
            status = .stale
            log("Telemetry expired after \(Int(maxReadingAge)) s.")
        }

        if let request = pending, now >= request.deadline {
            let recovered = decoder.finishBurst()
            consume(recovered)
            if pending != nil {
                pending = nil
                handleTimeout(request.command, now: now)
            }
        }

        guard pending == nil, now >= nextRequestAt else { return }
        if case .diagnostics = status { return }

        let command: VESCRequest = firmware == nil ? .firmwareVersion : .bmsValues
        guard bluetooth.send(command) else { return }
        pending = PendingRequest(command: command, deadline: now + 3)
        nextRequestAt = now + refreshSeconds

        if command == .firmwareVersion { identityAttempts += 1 }
        if command == .firmwareVersion || captureRawNotifications {
            log("TX \(command.label) (\(command.rawValue)), no arguments.")
        }
    }

    private func handleTimeout(_ command: VESCRequest, now: TimeInterval) {
        log("Reply timeout for \(command.label).")
        switch command {
        case .firmwareVersion:
            if identityAttempts >= 3 {
                status = .diagnostics("The device did not answer the firmware query. Check the BLE link, then reconnect.")
            } else {
                nextRequestAt = now + 1
            }
        case .bmsValues:
            if telemetry == nil, lastSampleAt == nil {
                status = .unavailable("No BMS telemetry reply yet. Review Diagnostics for details.")
            }
            backOff(now: now)
        }
    }

    private func consume(_ batch: VESCPacketCodec.Batch) {
        batch.problems.forEach { log($0) }
        for payload in batch.payloads {
            guard let request = pending, payload.first == request.command.rawValue else {
                if let command = payload.first { log("Ignored unexpected reply \(command) (\(payload.count) bytes).") }
                continue
            }
            pending = nil
            // A completed reply ends the request. Never carry partial bytes to
            // the next command, where they could hide a valid response.
            decoder = VESCPacketCodec.Stream()
            switch request.command {
            case .firmwareVersion: acceptIdentity(payload)
            case .bmsValues: acceptTelemetry(payload)
            }
        }
    }

    private func acceptIdentity(_ payload: [UInt8]) {
        do {
            let identity = try VESCProtocol.firmwareIdentity(from: payload)
            firmware = identity
            log("Firmware reply: \(identity.hardwareName) \(identity.versionLabel), hardware type \(identity.hardwareType.map(String.init) ?? "unknown"), name \(identity.firmwareName ?? "absent").")
            if identity.isHarmony16 {
                status = .waiting
                nextRequestAt = uptime
            } else {
                status = .diagnostics("The firmware reply does not identify a Harmony 16. The VESC link is available for diagnostics.")
            }
        } catch {
            log("Firmware decode: \(error)")
            if identityAttempts >= 3 {
                status = .diagnostics("Unable to verify the firmware reply. Review Diagnostics, then reconnect.")
            } else {
                nextRequestAt = uptime + 1
            }
        }
    }

    private func acceptTelemetry(_ payload: [UInt8]) {
        do {
            let values = try VESCProtocol.bmsValues(from: payload)
            if status != .live {
                log("Accepted BMS revision \(values.dataVersion), \(values.groups.count) groups, \(values.temperatures.externalNTCs.count) cell NTCs (\(payload.count) bytes).")
            }
            telemetry = values
            lastSampleAt = uptime
            lastSuccessfulUpdate = Date()
            status = .live
            consecutiveMisses = 0
        } catch {
            telemetry = nil
            log("Telemetry decode (\(payload.count) bytes): \(error)")
            status = .unavailable(String(describing: error))
            backOff(now: uptime)
        }
    }

    private func backOff(now: TimeInterval) {
        consecutiveMisses = min(consecutiveMisses + 1, 3)
        let interval = consecutiveMisses >= 3 ? 5 : Double(refreshRate.rawValue)
        nextRequestAt = now + interval
    }

    private func resetLinkState() {
        decoder = VESCPacketCodec.Stream()
        firmware = nil
        telemetry = nil
        pending = nil
        nextRequestAt = 0
        lastSampleAt = nil
        identityAttempts = 0
        consecutiveMisses = 0
    }

    private func log(_ message: String) {
        let entry = LogEntry(id: nextLogID, time: Date(), message: message)
        nextLogID += 1
        logs.append(entry)
        if logs.count > 350 { logs.removeFirst(logs.count - 350) }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", Int($0)) }.joined(separator: " ")
    }
}
