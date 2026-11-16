// SPDX-License-Identifier: GPL-3.0-or-later
@preconcurrency import CoreBluetooth
import Foundation
import Observation

@MainActor
@Observable
final class BLEManager: NSObject {
    enum Radio: Equatable {
        case idle, starting, ready, off, denied, unavailable

        var message: String {
            switch self {
            case .idle: "Bluetooth starts when you scan."
            case .starting: "Waiting for Bluetooth."
            case .ready: "Bluetooth is ready."
            case .off: "Turn on Bluetooth in iPhone Settings."
            case .denied: "Allow Bluetooth for Harmony Monitor in iPhone Settings."
            case .unavailable: "Bluetooth is unavailable on this device."
            }
        }
    }

    enum Phase: Equatable {
        case disconnected, connecting, discovering, notifications, ready, inspecting, reconnecting, disconnecting

        var label: String {
            switch self {
            case .disconnected: "Disconnected"
            case .connecting: "Connecting"
            case .discovering: "Discovering services"
            case .notifications: "Enabling notifications"
            case .ready: "Connected"
            case .inspecting: "Diagnostics only"
            case .reconnecting: "Reconnecting"
            case .disconnecting: "Disconnecting"
            }
        }
    }

    enum Intent: Equatable { case monitor, inspect }

    struct Device: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int?
        let advertisesUART: Bool
    }

    struct Characteristic: Identifiable {
        let id: ObjectIdentifier
        let uuid: String
        let properties: String
        let isNotifying: Bool
        let canListen: Bool
        let changingSubscription: Bool
    }

    struct Service: Identifiable {
        let id: ObjectIdentifier
        let uuid: String
        let characteristics: [Characteristic]
    }

    enum Event {
        case log(String)
        case ready
        case ended
        case inspect(String)
        case notification(uuid: String, data: Data, isVESC: Bool)
    }

    private(set) var radio: Radio = .idle
    private(set) var phase: Phase = .disconnected
    private(set) var isScanning = false
    private(set) var devices: [Device] = []
    private(set) var services: [Service] = []
    private(set) var target: Device?

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var discovered: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var selected: CBPeripheral?
    @ObservationIgnored private var active: CBPeripheral?
    @ObservationIgnored private var intent: Intent = .monitor
    @ObservationIgnored private var uartInput: CBCharacteristic?
    @ObservationIgnored private var uartOutput: CBCharacteristic?
    @ObservationIgnored private var pendingServices: Set<ObjectIdentifier> = []
    @ObservationIgnored private var pendingSubscriptions: Set<ObjectIdentifier> = []
    @ObservationIgnored private var writeDeadline: TimeInterval?
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var scanDeadline: TimeInterval?
    @ObservationIgnored private var linkDeadline: TimeInterval?
    @ObservationIgnored private var reconnectAt: TimeInterval?
    @ObservationIgnored private var reconnectAttempts = 0
    @ObservationIgnored private var inForeground = true
    @ObservationIgnored private var autoReconnect = true

    private static let uart = CBUUID(string: VESCProtocol.uartService)
    private static let writeUUID = CBUUID(string: VESCProtocol.uartWrite)
    private static let notifyUUID = CBUUID(string: VESCProtocol.uartNotify)
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func startScan() {
        guard inForeground, phase == .disconnected else { return }
        wantsScan = true
        if central == nil {
            radio = .starting
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            startScanIfPossible()
        }
    }

    func stopScan() {
        wantsScan = false
        scanDeadline = nil
        if isScanning {
            central?.stopScan()
            isScanning = false
            onEvent?(.log("BLE scan ended."))
        }
    }

    func connect(_ device: Device, intent: Intent) {
        guard phase == .disconnected, active == nil,
              let peripheral = discovered[device.id], radio == .ready else { return }
        stopScan()
        selected = peripheral
        target = device
        self.intent = intent
        reconnectAttempts = 0
        reconnectAt = nil
        beginLink(peripheral)
        discovered.removeAll()
        devices.removeAll()
    }

    func disconnect() {
        stopScan()
        selected = nil
        target = nil
        reconnectAt = nil
        reconnectAttempts = 0
        cancelLink()
    }

    func setAutomaticReconnect(_ enabled: Bool) {
        autoReconnect = enabled
        if !enabled, phase == .reconnecting {
            reconnectAt = nil
            phase = .disconnected
        }
    }

    func setForeground(_ foreground: Bool) {
        guard inForeground != foreground else { return }
        inForeground = foreground

        if foreground {
            reconnectAttempts = 0
            if active == nil { scheduleReconnect() }
        } else {
            stopScan()
            reconnectAt = nil
            if !autoReconnect { selected = nil }
            cancelLink()
        }
    }

    func tick(_ now: TimeInterval) {
        if let scanDeadline, now >= scanDeadline { stopScan() }
        if let writeDeadline, now >= writeDeadline {
            self.writeDeadline = nil
            enterDiagnostics("BLE write acknowledgement timed out. Reconnect and complete any iOS pairing prompt.")
        }
        if let reconnectAt, now >= reconnectAt, let selected {
            self.reconnectAt = nil
            beginLink(selected)
        }
        if let linkDeadline, now >= linkDeadline {
            self.linkDeadline = nil
            switch phase {
            case .connecting:
                onEvent?(.log("BLE connection attempt timed out."))
                cancelLink()
            case .discovering, .notifications:
                enterDiagnostics("BLE discovery or notification subscription timed out.")
            default:
                break
            }
        }
    }

    @discardableResult
    func send(_ request: VESCRequest) -> Bool {
        guard phase == .ready, inForeground, writeDeadline == nil,
              let active, let uartInput,
              let frame = VESCPacketCodec.encode([request.rawValue]) else { return false }
        let type: CBCharacteristicWriteType = uartInput.properties.contains(.write)
            ? .withResponse : .withoutResponse

        guard frame.count <= active.maximumWriteValueLength(for: type) else {
            enterDiagnostics("BLE write limit is smaller than a VESC request.")
            return false
        }
        if type == .withoutResponse, !active.canSendWriteWithoutResponse { return false }

        writeDeadline = type == .withResponse ? uptime + 30 : nil
        active.writeValue(Data(frame), for: uartInput, type: type)
        return true
    }

    func setDiagnosticListening(_ enabled: Bool, for id: ObjectIdentifier) {
        guard let active, [.ready, .inspecting].contains(phase),
              !pendingSubscriptions.contains(id),
              let characteristic = active.services?.compactMap(\.characteristics).flatMap({ $0 })
                .first(where: { ObjectIdentifier($0) == id }),
              uartOutput !== characteristic,
              characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
        else { return }

        pendingSubscriptions.insert(id)
        refreshServices()
        active.setNotifyValue(enabled, for: characteristic)
    }

    private func startScanIfPossible() {
        guard wantsScan, !isScanning, let central, central.state == .poweredOn else { return }
        discovered.removeAll()
        devices.removeAll()
        isScanning = true
        scanDeadline = uptime + 12
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        onEvent?(.log("Scanning for nearby BLE devices."))
    }

    private func beginLink(_ peripheral: CBPeripheral) {
        guard let central, radio == .ready, inForeground, active == nil else {
            phase = .disconnected
            return
        }

        active = peripheral
        peripheral.delegate = self
        phase = .connecting
        linkDeadline = uptime + 12
        onEvent?(.log("Connecting to \(target?.name ?? "BLE device") (\(peripheral.identifier.uuidString))."))
        central.connect(peripheral, options: nil)
    }

    private func cancelLink() {
        linkDeadline = nil
        writeDeadline = nil
        if let active {
            phase = .disconnecting
            central?.cancelPeripheralConnection(active)
        } else {
            phase = .disconnected
        }
        onEvent?(.ended)
    }

    private func finishLink(_ peripheral: CBPeripheral, error: Error?) {
        guard active === peripheral else { return }
        if let error { onEvent?(.log("BLE link ended: \(error.localizedDescription)")) }
        else { onEvent?(.log("BLE link ended.")) }

        peripheral.delegate = nil
        active = nil
        linkDeadline = nil
        phase = .disconnected
        clearGATT()
        onEvent?(.ended)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard autoReconnect, inForeground, selected != nil, intent == .monitor,
              active == nil, radio == .ready, reconnectAt == nil else { return }
        let delays: [TimeInterval] = [1, 2, 4]
        guard reconnectAttempts < delays.count else {
            onEvent?(.log("Automatic reconnect attempts ended. Use Connect to scan again."))
            selected = nil
            return
        }
        let delay = delays[reconnectAttempts]
        reconnectAttempts += 1
        reconnectAt = uptime + delay
        phase = .reconnecting
        onEvent?(.log("Reconnect attempt \(reconnectAttempts) in \(Int(delay)) s."))
    }

    private func enterDiagnostics(_ reason: String) {
        phase = .inspecting
        linkDeadline = nil
        uartInput = nil
        uartOutput = nil
        writeDeadline = nil
        refreshServices()
        onEvent?(.log(reason))
        onEvent?(.inspect(reason))
    }

    private func clearGATT() {
        pendingServices.removeAll()
        pendingSubscriptions.removeAll()
        uartInput = nil
        uartOutput = nil
        writeDeadline = nil
        services.removeAll()
    }

    private func refreshServices() {
        services = (active?.services ?? []).map { service in
            let characteristics = (service.characteristics ?? []).map { characteristic in
                let id = ObjectIdentifier(characteristic)
                let properties = characteristic.properties
                let flags: [(CBCharacteristicProperties, String)] = [
                    (.read, "read"), (.write, "write"), (.writeWithoutResponse, "write without response"),
                    (.notify, "notify"), (.indicate, "indicate"),
                    (.notifyEncryptionRequired, "notify requires encryption"),
                    (.indicateEncryptionRequired, "indicate requires encryption")
                ]
                let details = flags.filter { properties.contains($0.0) }.map(\.1)
                return Characteristic(
                    id: id, uuid: characteristic.uuid.uuidString,
                    properties: details.isEmpty ? "Other properties (\(properties.rawValue))" : details.joined(separator: ", "),
                    isNotifying: characteristic.isNotifying,
                    canListen: (phase == .ready || phase == .inspecting) && characteristic !== uartOutput
                        && (properties.contains(.notify) || properties.contains(.indicate)),
                    changingSubscription: pendingSubscriptions.contains(id)
                )
            }
            return Service(id: ObjectIdentifier(service), uuid: service.uuid.uuidString, characteristics: characteristics)
        }
    }

    private func discoveryComplete(_ peripheral: CBPeripheral) {
        guard phase == .discovering else { return }
        guard intent == .monitor else {
            enterDiagnostics("Passive inspection. Select a notification characteristic in Diagnostics to listen.")
            return
        }

        let matching = (peripheral.services ?? []).filter { $0.uuid == Self.uart }
        guard matching.count == 1, let characteristics = matching.first?.characteristics else {
            enterDiagnostics("The verified VESC UART service was missing or ambiguous.")
            return
        }

        let inputs = characteristics.filter { $0.uuid == Self.writeUUID }
        let outputs = characteristics.filter { $0.uuid == Self.notifyUUID }
        guard inputs.count == 1, outputs.count == 1, let input = inputs.first, let output = outputs.first,
              input.properties.contains(.write) || input.properties.contains(.writeWithoutResponse),
              output.properties.contains(.notify) else {
            enterDiagnostics("VESC UART characteristics are missing or have unexpected properties.")
            return
        }

        uartInput = input
        uartOutput = output
        phase = .notifications
        linkDeadline = uptime + 30
        onEvent?(.log("Subscribing to VESC TX \(output.uuid.uuidString)."))
        peripheral.setNotifyValue(true, for: output)
    }
}

extension BLEManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: radio = .ready
        case .poweredOff: radio = .off
        case .unauthorized: radio = .denied
        case .unsupported: radio = .unavailable
        case .unknown, .resetting: radio = .starting
        @unknown default: radio = .unavailable
        }
        onEvent?(.log(radio.message))
        if radio == .ready {
            if wantsScan { startScanIfPossible() }
            else { scheduleReconnect() }
        } else {
            // CoreBluetooth invalidates connections when the radio resets.
            isScanning = false
            scanDeadline = nil
            active?.delegate = nil
            active = nil
            linkDeadline = nil
            reconnectAt = nil
            phase = .disconnected
            clearGATT()
            onEvent?(.ended)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning, advertisementData[CBAdvertisementDataIsConnectable] as? Bool != false else { return }
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let device = Device(
            id: peripheral.identifier,
            name: (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unnamed BLE device",
            rssi: RSSI.intValue == 127 ? nil : RSSI.intValue,
            advertisesUART: advertised.contains(Self.uart)
        )
        discovered[device.id] = peripheral
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active === peripheral, phase == .connecting else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        phase = .discovering
        linkDeadline = uptime + 10
        onEvent?(.log("BLE connected. Discovering GATT services."))
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishLink(peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finishLink(peripheral, error: error)
    }
}

extension BLEManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard active === peripheral, phase == .discovering else { return }
        if let error {
            enterDiagnostics("BLE services error: \(error.localizedDescription)")
            return
        }
        let found = peripheral.services ?? []
        refreshServices()
        onEvent?(.log("GATT services: \(found.map { $0.uuid.uuidString }.joined(separator: ", "))."))
        pendingServices = Set(found.map { ObjectIdentifier($0) })
        if found.isEmpty { discoveryComplete(peripheral) }
        else { found.forEach { peripheral.discoverCharacteristics(nil, for: $0) } }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard active === peripheral, phase == .discovering || phase == .inspecting else { return }
        pendingServices.remove(ObjectIdentifier(service))
        refreshServices()
        if let error {
            onEvent?(.log("GATT \(service.uuid.uuidString): \(error.localizedDescription)"))
            if phase == .discovering, intent == .monitor, service.uuid == Self.uart {
                enterDiagnostics("Unable to discover the VESC UART characteristics.")
                return
            }
        } else {
            let details = services.first { $0.id == ObjectIdentifier(service) }?.characteristics ?? []
            for item in details { onEvent?(.log("GATT \(service.uuid.uuidString) / \(item.uuid) [\(item.properties)]")) }
        }
        if pendingServices.isEmpty { discoveryComplete(peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard active === peripheral, phase != .disconnecting else { return }
        pendingSubscriptions.remove(ObjectIdentifier(characteristic))
        if let error { onEvent?(.log("Notify \(characteristic.uuid.uuidString): \(error.localizedDescription)")) }
        else { onEvent?(.log("Notify \(characteristic.uuid.uuidString): \(characteristic.isNotifying ? "on" : "off").")) }

        if characteristic === uartOutput {
            guard error == nil, characteristic.isNotifying else {
                enterDiagnostics("VESC notifications are unavailable. Check the BLE link and any iOS pairing prompt.")
                return
            }
            if phase == .notifications {
                phase = .ready
                linkDeadline = nil
                reconnectAttempts = 0
                refreshServices()
                onEvent?(.ready)
                return
            }
        }
        refreshServices()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active === peripheral, phase == .ready || phase == .inspecting else { return }
        if let error { onEvent?(.log("BLE RX \(characteristic.uuid.uuidString): \(error.localizedDescription)")) }
        else if let value = characteristic.value, !value.isEmpty {
            let isVESC = phase == .ready && characteristic === uartOutput
            onEvent?(.notification(uuid: characteristic.uuid.uuidString, data: value, isVESC: isVESC))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active === peripheral, characteristic === uartInput else { return }
        writeDeadline = nil
        if let error { onEvent?(.log("VESC write error: \(error.localizedDescription)")) }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard active === peripheral, phase != .disconnecting else { return }
        onEvent?(.log("Peripheral changed its BLE services. Closing the link for fresh discovery."))
        cancelLink()
    }
}
