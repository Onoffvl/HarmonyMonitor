// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
#if SWIFT_PACKAGE
@testable import HarmonyCore
#else
@testable import HarmonyMonitor
#endif

final class TelemetryTests: XCTestCase {
    func testHarmonyIdentity() throws {
        let fw = try VESCProtocol.firmwareIdentity(from: Fixtures.firmware)
        XCTAssertEqual(fw.hardwareName, "VBMS16")
        XCTAssertEqual(fw.hardwareType, 2)
        XCTAssertEqual(fw.firmwareName, "harmony")
        XCTAssertEqual(fw.versionLabel, "6.06")
        XCTAssertTrue(fw.isHarmony16)
    }

    func testIdentityRejectsOtherHardwareAndFirmware() throws {
        var payload = Fixtures.firmware
        payload[7] = 0x33
        XCTAssertFalse(try VESCProtocol.firmwareIdentity(from: payload).isHarmony16)
        payload = Fixtures.firmware
        payload[24] = 1
        XCTAssertFalse(try VESCProtocol.firmwareIdentity(from: payload).isHarmony16)
        payload = Fixtures.firmware
        payload[30] = 0x78
        XCTAssertFalse(try VESCProtocol.firmwareIdentity(from: payload).isHarmony16)
    }

    func testIdentityWithMissingOptionalNameRequiresMatchingHardwareType() throws {
        XCTAssertTrue(try VESCProtocol.firmwareIdentity(from: Array(Fixtures.firmware.prefix(25))).isHarmony16)
        XCTAssertFalse(try VESCProtocol.firmwareIdentity(from: Array(Fixtures.firmware.prefix(10))).isHarmony16)
        XCTAssertThrowsError(try VESCProtocol.firmwareIdentity(from: Array(Fixtures.firmware.prefix(11))))
    }

    func testTelemetryScalesCurrentAndCellReadings() throws {
        let values = try VESCProtocol.bmsValues(from: Fixtures.telemetry)
        XCTAssertEqual(values.packVoltage, 25.901, accuracy: 0.000001)
        XCTAssertEqual(values.packCurrent, 12.345678, accuracy: 0.000001)
        XCTAssertEqual(values.stateOfCharge, 0.637)
        XCTAssertEqual(values.groups.map(\.id), Array(1...7))
        XCTAssertEqual(values.groups.map(\.millivolts), [3697, 3702, 3699, 3700, 3704, 3701, 3698])
        XCTAssertEqual(values.groups.filter(\.balancing).map(\.id), [2, 5])
        XCTAssertEqual(values.lowest?.id, 1)
        XCTAssertEqual(values.highest?.id, 5)
        XCTAssertEqual(values.spreadMillivolts, 7)
        XCTAssertEqual(values.flow, .discharging)
    }

    func testTemperatureMappingAndFaultTokens() throws {
        let values = try VESCProtocol.bmsValues(from: Fixtures.telemetry)
        XCTAssertEqual(values.temperatures.ic, 31.42)
        XCTAssertEqual(values.temperatures.minimumCell, 23.28)
        XCTAssertEqual(values.temperatures.maximumCell, 28.41)
        XCTAssertEqual(values.temperatures.mosfet, 34.56)
        XCTAssertNil(values.temperatures.ambient)
        XCTAssertEqual(values.temperatures.externalNTCs, [23.28, 28.41])
        XCTAssertEqual(values.status?.faults, [.switchOvertemperature, .chargeOvercurrent])
        XCTAssertEqual(values.status?.raw, "FLT_PSW_OT | FLT_CHG_OC | BAL")
    }

    func testNegativeCurrentAndGenuineZeroSOC() throws {
        var payload = Fixtures.telemetry
        payload.replaceSubrange(13..<17, with: Fixtures.hex("FF 85 EE 00"))
        payload.replaceSubrange(70..<72, with: [0, 0])
        let values = try VESCProtocol.bmsValues(from: payload)
        XCTAssertEqual(values.packCurrent, -8, accuracy: 0.000001)
        XCTAssertEqual(values.flow, .charging)
        XCTAssertEqual(values.stateOfCharge, 0)
        payload.replaceSubrange(13..<17, with: [0, 0, 0, 0])
        XCTAssertEqual(try VESCProtocol.bmsValues(from: payload).flow, .idle)
    }

    func testFirmwareTemperatureFallbackAndInvalidSensor() throws {
        var payload = Fixtures.telemetry
        payload.replaceSubrange(58..<62, with: Fixtures.hex("FF 9C FF 9C"))
        let failed = try VESCProtocol.bmsValues(from: payload)
        XCTAssertEqual(failed.temperatures.externalNTCs, [nil, nil])
        XCTAssertNil(failed.temperatures.maximumCell)

        payload[47] = 5
        payload.replaceSubrange(68..<70, with: Fixtures.hex("09 60")) // 24.00 C
        payload.removeSubrange(58..<62)
        let withoutSensors = try VESCProtocol.bmsValues(from: payload)
        XCTAssertEqual(withoutSensors.temperatures.externalNTCs, [])
        XCTAssertNil(withoutSensors.temperatures.maximumCell)
        XCTAssertNil(withoutSensors.temperatures.minimumCell)
    }

    func testEveryTruncatedTelemetryPrefixFails() {
        for length in 0..<Fixtures.telemetry.count {
            XCTAssertThrowsError(try VESCProtocol.bmsValues(from: Array(Fixtures.telemetry.prefix(length))),
                                 "prefix of \(length) bytes")
        }
    }

    func testUnsupportedLayoutAndPackCount() {
        var payload = Fixtures.telemetry
        payload[93] = 2
        XCTAssertThrowsError(try VESCProtocol.bmsValues(from: payload)) {
            XCTAssertEqual($0 as? VESCProtocol.DecodeError, .unsupportedDataVersion(2))
        }
        payload = Fixtures.telemetry + [0]
        XCTAssertThrowsError(try VESCProtocol.bmsValues(from: payload)) {
            XCTAssertEqual($0 as? VESCProtocol.DecodeError, .trailingBytes(1))
        }
        payload = Fixtures.telemetry
        payload[25] = 16
        XCTAssertThrowsError(try VESCProtocol.bmsValues(from: payload)) {
            XCTAssertEqual($0 as? VESCProtocol.DecodeError, .cellCount(16))
        }
        payload = Fixtures.telemetry
        payload[47] = 10
        XCTAssertThrowsError(try VESCProtocol.bmsValues(from: payload)) {
            XCTAssertEqual($0 as? VESCProtocol.DecodeError, .temperatureCount(10))
        }
    }

    func testInvalidBalancingFlagAndBadSoc() throws {
        var payload = Fixtures.telemetry
        payload[40] = 2
        XCTAssertThrowsError(try VESCProtocol.bmsValues(from: payload)) {
            XCTAssertEqual($0 as? VESCProtocol.DecodeError, .invalidBalanceFlag(2))
        }
        payload = Fixtures.telemetry
        payload.replaceSubrange(70..<72, with: [0xff, 0xff])
        XCTAssertNil(try VESCProtocol.bmsValues(from: payload).stateOfCharge)
    }

    func testInitializingValuesAndUnknownStatus() throws {
        var payload = Fixtures.telemetry
        payload.replaceSubrange(94..., with: Array("Initializing...".utf8) + [0])
        XCTAssertThrowsError(try VESCProtocol.bmsValues(from: payload)) {
            XCTAssertEqual($0 as? VESCProtocol.DecodeError, .notInitialized)
        }
        payload.replaceSubrange(94..., with: Array("SOMETHING_ELSE".utf8) + [0])
        let unmatched = try VESCProtocol.bmsValues(from: payload)
        XCTAssertEqual(unmatched.status?.raw, "SOMETHING_ELSE")
        XCTAssertEqual(unmatched.status?.faults, [])
    }
}
