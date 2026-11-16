// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
#if SWIFT_PACKAGE
@testable import HarmonyCore
#else
@testable import HarmonyMonitor
#endif

final class PacketTests: XCTestCase {
    func testCRCAndOutboundAllowlistFrames() {
        XCTAssertEqual(VESCPacketCodec.crc16("123456789".utf8), 0x31C3)
        XCTAssertEqual(VESCPacketCodec.encode([VESCRequest.firmwareVersion.rawValue]), Fixtures.hex("02 01 00 00 00 03"))
        XCTAssertEqual(VESCPacketCodec.encode([VESCRequest.bmsValues.rawValue]), Fixtures.hex("02 01 60 6C A6 03"))
        XCTAssertNil(VESCPacketCodec.encode([]))
    }

    func testFixtureChecksumsAndCoalescedFrames() {
        var stream = VESCPacketCodec.Stream()
        let result = stream.receive(Fixtures.firmwareFrame + Fixtures.telemetryFrame)
        XCTAssertEqual(result.payloads, [Fixtures.firmware, Fixtures.telemetry])
        XCTAssertTrue(result.problems.isEmpty)
        XCTAssertEqual(VESCPacketCodec.encode(Fixtures.telemetry), Fixtures.telemetryFrame)
    }

    func testEveryFragmentBoundary() {
        let frame = Fixtures.telemetryFrame
        for split in 1..<frame.count {
            var stream = VESCPacketCodec.Stream()
            let first = stream.receive(frame.prefix(split))
            XCTAssertTrue(first.payloads.isEmpty, "split \(split)")
            XCTAssertTrue(first.problems.isEmpty, "split \(split)")
            let second = stream.receive(frame.dropFirst(split))
            XCTAssertEqual(second.payloads, [Fixtures.telemetry], "split \(split)")
            XCTAssertTrue(second.problems.isEmpty, "split \(split)")
        }
    }

    func testBadCRCThenGoodPacket() throws {
        var broken = try XCTUnwrap(VESCPacketCodec.encode([96]))
        broken[3] ^= 1
        var stream = VESCPacketCodec.Stream()
        let result = stream.receive(broken + Fixtures.firmwareFrame)
        XCTAssertTrue(result.problems.contains { $0.contains("CRC mismatch") })
        XCTAssertEqual(result.payloads, [Fixtures.firmware])
    }

    func testBadStopByteThenGoodPacket() throws {
        var broken = try XCTUnwrap(VESCPacketCodec.encode([96]))
        broken[broken.count - 1] = 0x00
        var stream = VESCPacketCodec.Stream()
        let result = stream.receive(broken + Fixtures.firmwareFrame)
        XCTAssertTrue(result.problems.contains { $0.contains("stop byte") })
        XCTAssertEqual(result.payloads, [Fixtures.firmware])
    }

    func testRecoveryAfterBrokenLengthAndNoise() {
        var stream = VESCPacketCodec.Stream()
        let before = stream.receive([0xff, 0, 2, 250, 96] + Fixtures.telemetryFrame)
        XCTAssertTrue(before.payloads.isEmpty)
        XCTAssertTrue(before.problems.contains { $0.contains("Skipped 2") })
        let after = stream.finishBurst()
        XCTAssertEqual(after.payloads, [Fixtures.telemetry])
        XCTAssertTrue(after.problems.contains { $0.contains("incomplete") })
        XCTAssertTrue(stream.finishBurst().payloads.isEmpty)
    }

    func testInvalidLengths() {
        var stream = VESCPacketCodec.Stream()
        let result = stream.receive([2, 0, 3, 2, 1] + Fixtures.firmwareFrame)
        let recovered = stream.finishBurst()
        XCTAssertTrue(result.problems.contains { $0.contains("length 0") })
        XCTAssertTrue(result.problems.contains { $0.contains("length 513") })
        XCTAssertEqual(result.payloads + recovered.payloads, [Fixtures.firmware])
    }

    func testWireLengthWidthsAndBoundaries() throws {
        for (length, header) in [
            (255, [UInt8(2), 255]),
            (256, [UInt8(3), 1, 0]),
            (65_535, [UInt8(3), 255, 255]),
            (65_536, [UInt8(4), 1, 0, 0])
        ] {
            let payload = [UInt8](repeating: 0xA6, count: length)
            let frame = try XCTUnwrap(VESCPacketCodec.encode(payload))
            XCTAssertEqual(Array(frame.prefix(header.count)), header)
            var stream = VESCPacketCodec.Stream(maximumPayload: length)
            XCTAssertTrue(stream.receive(frame.prefix(header.count - 1)).payloads.isEmpty)
            let remaining = stream.receive(frame.dropFirst(header.count - 1))
            XCTAssertEqual(remaining.payloads, [payload])
            XCTAssertTrue(remaining.problems.isEmpty)
        }
    }
}
