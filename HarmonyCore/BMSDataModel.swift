// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct FirmwareIdentity: Equatable {
    let major: UInt8
    let minor: UInt8
    let hardwareName: String
    let hardwareType: UInt8?
    let firmwareName: String?
    let testVersion: UInt8?

    var isHarmony16: Bool {
        hardwareName.lowercased() == "vbms16"
            && hardwareType == 2
            && ["harmony", ""].contains(firmwareName?.lowercased() ?? "")
    }

    var versionLabel: String {
        let minorLabel = minor < 10 ? "0\(minor)" : "\(minor)"
        let version = "\(major).\(minorLabel)"
        guard let testVersion, testVersion > 0 else { return version }
        return "\(version) (test \(testVersion))"
    }
}

struct BMSDataModel: Equatable {
    struct Group: Equatable, Identifiable {
        let id: Int
        let millivolts: Int
        let balancing: Bool

        var volts: Double { Double(millivolts) / 1_000 }
    }

    struct Temperatures: Equatable {
        let ic: Double?
        let minimumCell: Double?
        let maximumCell: Double?
        let mosfet: Double?
        let ambient: Double?
        let externalNTCs: [Double?]
    }

    enum Flow: String {
        case charging = "Charging"
        case discharging = "Discharging"
        case idle = "Idle"
    }

    struct Status: Equatable {
        enum Fault: String, CaseIterable {
            case shortCircuit = "FLT_PSW_SHORT"
            case switchOvertemperature = "FLT_PSW_OT"
            case precharge = "FLT_PCHG"
            case chargeOvercurrent = "FLT_CHG_OC"

            var title: String {
                switch self {
                case .shortCircuit: "Power switch short circuit"
                case .switchOvertemperature: "Power switch overtemperature"
                case .precharge: "Precharge fault"
                case .chargeOvercurrent: "Charge overcurrent"
                }
            }
        }

        let raw: String

        var faults: [Fault] {
            let tokens = raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            return Fault.allCases.filter { tokens.contains($0.rawValue) }
        }
    }

    let packVoltage: Double
    let packCurrent: Double
    let stateOfCharge: Double?
    let groups: [Group]
    let temperatures: Temperatures
    let status: Status?
    let dataVersion: UInt8

    // Display deadband for near-zero current. The signed reading stays intact.
    var flow: Flow {
        if packCurrent >= 0.10 { return .discharging }
        if packCurrent <= -0.10 { return .charging }
        return .idle
    }

    var lowest: Group? { groups.min { $0.millivolts < $1.millivolts } }
    var highest: Group? { groups.max { $0.millivolts < $1.millivolts } }

    var spreadMillivolts: Int? {
        guard let lowest, let highest else { return nil }
        return highest.millivolts - lowest.millivolts
    }
}
