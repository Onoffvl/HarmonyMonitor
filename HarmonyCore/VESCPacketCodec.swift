// SPDX-License-Identifier: GPL-3.0-or-later
// Swift implementation of the wire framing in VESC packet.c, copyright
// 2016–2021 Benjamin Vedder. See Docs/Protocol.md for upstream sources.

enum VESCPacketCodec {
    static func crc16(_ bytes: some Collection<UInt8>) -> UInt16 {
        var remainder: UInt16 = 0
        for byte in bytes {
            remainder ^= UInt16(byte) << 8
            for _ in 0..<8 {
                let highBit = remainder & 0x8000 != 0
                remainder <<= 1
                if highBit { remainder ^= 0x1021 }
            }
        }
        return remainder
    }

    static func encode(_ payload: [UInt8]) -> [UInt8]? {
        let count = payload.count
        guard (1...0xFF_FF_FF).contains(count) else { return nil }

        let length = UInt8(truncatingIfNeeded: count)
        var frame: [UInt8]
        switch count {
        case ...255:
            frame = [2, length]
        case ...65_535:
            frame = [3, UInt8(count >> 8), length]
        default:
            frame = [4, UInt8(count >> 16), UInt8(truncatingIfNeeded: count >> 8), length]
        }

        let crc = crc16(payload)
        frame.append(contentsOf: payload)
        frame.append(contentsOf: [UInt8(crc >> 8), UInt8(truncatingIfNeeded: crc), 3])
        return frame
    }

    struct Batch {
        var payloads: [[UInt8]] = []
        var problems: [String] = []
    }

    struct Stream {
        // VESC Express defaults to 512 bytes. Both requests supported here
        // have small replies, so this also bounds buffering after a corrupt length.
        private let maximumPayload: Int
        private var buffer: [UInt8] = []

        init(maximumPayload: Int = 512) {
            self.maximumPayload = min(max(maximumPayload, 1), 0xFF_FF_FF)
        }

        mutating func receive(_ bytes: some Collection<UInt8>) -> Batch {
            buffer.append(contentsOf: bytes)
            return drain(atTimeout: false)
        }

        // After a reply deadline, try resynchronizing past any incomplete frame.
        mutating func finishBurst() -> Batch {
            drain(atTimeout: true)
        }

        private mutating func drain(atTimeout: Bool) -> Batch {
            var batch = Batch()
            var offset = 0
            var noise = 0
            var incomplete = 0

            while offset < buffer.count {
                let headerSize = Int(buffer[offset])
                guard (2...4).contains(headerSize) else {
                    noise += 1
                    offset += 1
                    continue
                }

                guard offset + headerSize <= buffer.count else {
                    if !atTimeout { break }
                    incomplete += 1
                    offset += 1
                    continue
                }

                let body = offset + headerSize
                let length = buffer[(offset + 1)..<body].reduce(0) { ($0 << 8) | Int($1) }
                // The VESC receiver also accepts the two boundary lengths
                // 255 and 65,535 in the next larger framing format.
                let minimumLength = [1, 255, 65_535][headerSize - 2]
                guard minimumLength <= length, length <= maximumPayload else {
                    batch.problems.append("Invalid VESC frame length \(length) (header \(headerSize)).")
                    offset += 1
                    continue
                }

                let crcIndex = body + length
                let end = crcIndex + 3
                guard end <= buffer.count else {
                    if !atTimeout { break }
                    incomplete += 1
                    offset += 1
                    continue
                }

                guard buffer[end - 1] == 3 else {
                    batch.problems.append("VESC frame missing stop byte (payload \(length) bytes).")
                    offset += 1
                    continue
                }

                let payload = buffer[body..<crcIndex]
                let receivedCRC = UInt16(buffer[crcIndex]) << 8 | UInt16(buffer[crcIndex + 1])
                guard VESCPacketCodec.crc16(payload) == receivedCRC else {
                    batch.problems.append("VESC CRC mismatch (payload \(length) bytes).")
                    offset += 1
                    continue
                }

                batch.payloads.append(Array(payload))
                offset = end
            }

            if noise > 0 { batch.problems.append("Skipped \(noise) byte(s) outside VESC framing.") }
            if incomplete > 0 { batch.problems.append("Discarded \(incomplete) incomplete VESC header(s) at reply timeout.") }
            buffer.removeFirst(offset)
            return batch
        }
    }
}
