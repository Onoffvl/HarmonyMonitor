// SPDX-License-Identifier: GPL-3.0-or-later

enum Fixtures {
    // Constructed offline from the upstream encoder layout. These are test
    // vectors, not recordings. Frame checksums were generated with Python's
    // binascii.crc_hqx and are independent of the Swift codec.
    static let firmwareFrame = hex("""
        02 2A 00 06 06 56 42 4D 53 31 36 00 00 01 02 03 04 05
        06 07 08 09 0A 0B 00 00 02 02 00 01 00 00 68 61 72 6D
        6F 6E 79 00 12 34 56 78 4C 9B 03
        """)
    static let telemetryFrame = hex("""
        02 7C 60 01 8B 37 C8 01 A0 90 A0 FF F0 C5 90 00 BC 61
        4E 00 00 06 D8 00 00 39 DF 07 0E 71 0E 76 0E 73 0E 74
        0E 78 0E 75 0E 72 00 01 00 00 01 00 00 07 0C 46 09 18
        0B 19 0D 80 8A D0 09 18 0B 19 0C 46 09 C4 11 94 0B 19
        02 7D 03 E8 17 40 B0 00 00 43 16 00 00 40 80 00 00 42
        BE 00 00 00 00 01 46 4C 54 5F 50 53 57 5F 4F 54 20 7C
        20 46 4C 54 5F 43 48 47 5F 4F 43 20 7C 20 42 41 4C 00
        FE E9 03
        """)

    static let firmware = Array(firmwareFrame.dropFirst(2).dropLast(3))
    static let telemetry = Array(telemetryFrame.dropFirst(2).dropLast(3))

    static func hex(_ text: String) -> [UInt8] {
        text.split(whereSeparator: { $0.isWhitespace }).map {
            guard let byte = UInt8($0, radix: 16) else { preconditionFailure("Invalid test hex byte.") }
            return byte
        }
    }
}
