// SPDX-License-Identifier: GPL-3.0-or-later
// Telemetry and firmware layouts from VESC Express by Benjamin Vedder and
// contributors. See Docs/Protocol.md for upstream sources and implementation limits.

// Keep this the entire outbound application command surface. The BLE transport
// takes a VESCRequest and cannot be given raw bytes or a command argument.
enum VESCRequest: UInt8 {
    case firmwareVersion = 0
    case bmsValues = 96

    var label: String {
        switch self {
        case .firmwareVersion: "COMM_FW_VERSION"
        case .bmsValues: "COMM_BMS_GET_VALUES"
        }
    }
}

enum VESCProtocol {
    static let groupCount = 7
    static let uartService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    static let uartWrite = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    static let uartNotify = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

    enum DecodeError: Error, Equatable, CustomStringConvertible {
        case wrongCommand
        case truncated(String)
        case invalidString(String)
        case trailingBytes(Int)
        case cellCount(Int)
        case temperatureCount(Int)
        case invalidBalanceFlag(UInt8)
        case unsupportedDataVersion(UInt8)
        case notInitialized

        var description: String {
            switch self {
            case .wrongCommand: "Unexpected VESC command in reply."
            case .truncated(let field): "Incomplete reply at \(field)."
            case .invalidString(let field): "Invalid NUL-terminated text at \(field)."
            case .trailingBytes(let count): "Unknown trailing fields (\(count) bytes)."
            case .cellCount(let count): "BMS reports \(count) series groups. This app expects seven."
            case .temperatureCount(let count): "Unexpected Harmony temperature field count (\(count))."
            case .invalidBalanceFlag(let flag): "Unexpected balance flag \(flag)."
            case .unsupportedDataVersion(let version): "Unsupported BMS data version \(version)."
            case .notInitialized: "BMS measurements are still initializing or missing."
            }
        }
    }

    static func firmwareIdentity(from payload: [UInt8]) throws -> FirmwareIdentity {
        var reader = Reader(payload)
        try reader.expect(.firmwareVersion)
        let major = try reader.byte("firmware major")
        let minor = try reader.byte("firmware minor")
        let hardware = try reader.text("hardware name", maximumLength: 64)
        guard !hardware.isEmpty else { throw DecodeError.invalidString("hardware name") }

        // VESC Tool treats the UUID and following fields as optional.
        // Verify identity only when the hardware type is present.
        if reader.remaining > 0 { try reader.skip(12, "firmware UUID") }
        let _ = reader.remaining > 0 ? try reader.byte("pairing flag") : nil
        let test = reader.remaining > 0 ? try reader.byte("test version") : nil
        let hardwareType = reader.remaining > 0 ? try reader.byte("hardware type") : nil
        // Custom config count, phase filters, HW/app UI flags, NRF flags.
        try reader.skip(min(5, reader.remaining), "firmware capability flags")
        let firmware = reader.remaining > 0 ? try reader.text("firmware name", maximumLength: 64) : nil
        if reader.remaining == 4 { try reader.skip(4, "hardware CRC") }
        try reader.expectEnd()

        return FirmwareIdentity(
            major: major, minor: minor, hardwareName: hardware,
            hardwareType: hardwareType, firmwareName: firmware, testVersion: test
        )
    }

    static func bmsValues(from payload: [UInt8]) throws -> BMSDataModel {
        var reader = Reader(payload)
        try reader.expect(.bmsValues)
        let packVoltage = Double(try reader.int32("pack voltage")) / 1_000_000
        try reader.skip(8, "charger voltage and forwarded current")
        let packCurrent = Double(try reader.int32("BMS shunt current")) / 1_000_000
        try reader.skip(8, "Ah and Wh counters")

        let count = Int(try reader.byte("series group count"))
        guard count == groupCount else { throw DecodeError.cellCount(count) }
        let millivolts = try (0..<count).map { _ in Int(try reader.int16("group voltage")) }
        let groups = try millivolts.enumerated().map { index, voltage in
            let flag = try reader.byte("balance flag")
            guard flag <= 1 else { throw DecodeError.invalidBalanceFlag(flag) }
            return BMSDataModel.Group(id: index + 1, millivolts: voltage, balancing: flag == 1)
        }

        let temperatureCount = Int(try reader.byte("temperature count"))
        // Harmony v1 sends five fixed entries followed by up to four cell NTCs.
        guard (5...9).contains(temperatureCount) else {
            throw DecodeError.temperatureCount(temperatureCount)
        }
        let readings = try (0..<temperatureCount).map { _ in try reader.int16("temperature channel") }
        let ic = try reader.int16("BMS IC temperature")
        try reader.skip(4, "humidity temperature and relative humidity")
        let hottest = try reader.int16("highest cell temperature")
        let soc = try reader.int16("SoC")
        try reader.skip(21, "SoH, CAN ID, lifetime counters and pressure")

        let version = try reader.byte("BMS data version")
        guard version == 1 else { throw DecodeError.unsupportedDataVersion(version) }
        let status = try reader.text("BMS status", maximumLength: 40)
        try reader.expectEnd()

        guard packVoltage > 0, millivolts.contains(where: { $0 > 0 }), status != "Initializing..." else {
            throw DecodeError.notInitialized
        }

        let external = readings.dropFirst(5).map(ntcTemperature)
        let hasCellTemperature = external.contains { $0 != nil }
        return BMSDataModel(
            packVoltage: packVoltage,
            packCurrent: packCurrent,
            stateOfCharge: (0...1_000).contains(soc) ? Double(soc) / 1_000 : nil,
            groups: groups,
            temperatures: BMSDataModel.Temperatures(
                ic: ic <= -27_315 ? nil : Double(ic) / 100,
                minimumCell: hasCellTemperature ? ntcTemperature(readings[1]) : nil,
                maximumCell: hasCellTemperature ? ntcTemperature(hottest) : nil,
                mosfet: ntcTemperature(readings[3]),
                ambient: ntcTemperature(readings[4]),
                externalNTCs: external
            ),
            status: status.isEmpty ? nil : BMSDataModel.Status(raw: status),
            dataVersion: version
        )
    }

    private static func ntcTemperature(_ raw: Int16) -> Double? {
        // VBMS16 hardware maps failed NTC conversions to -1 °C.
        // The Harmony script publishes -300 °C for an unavailable ambient sensor.
        guard raw != -100, raw > -27_315 else { return nil }
        return Double(raw) / 100
    }

    private struct Reader {
        private let bytes: [UInt8]
        private var offset = 0
        var remaining: Int { bytes.count - offset }

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func expect(_ command: VESCRequest) throws {
            guard try byte("command") == command.rawValue else { throw DecodeError.wrongCommand }
        }

        func expectEnd() throws {
            guard remaining == 0 else { throw DecodeError.trailingBytes(remaining) }
        }

        mutating func skip(_ count: Int, _ field: String) throws {
            guard remaining >= count else { throw DecodeError.truncated(field) }
            offset += count
        }

        mutating func byte(_ field: String) throws -> UInt8 {
            let start = offset
            try skip(1, field)
            return bytes[start]
        }

        mutating func int16(_ field: String) throws -> Int16 {
            Int16(bitPattern: UInt16(try unsigned(2, field)))
        }

        mutating func int32(_ field: String) throws -> Int32 {
            Int32(bitPattern: try unsigned(4, field))
        }

        private mutating func unsigned(_ count: Int, _ field: String) throws -> UInt32 {
            let start = offset
            try skip(count, field)
            return bytes[start..<offset].reduce(0) { ($0 << 8) | UInt32($1) }
        }

        mutating func text(_ field: String, maximumLength: Int) throws -> String {
            let candidates = bytes[offset...].prefix(maximumLength + 1)
            guard let end = candidates.firstIndex(of: 0),
                  bytes[offset..<end].allSatisfy({ (0x20...0x7E).contains($0) }) else {
                throw DecodeError.invalidString(field)
            }
            let text = String(decoding: bytes[offset..<end], as: UTF8.self)
            offset = end + 1
            return text
        }
    }
}
