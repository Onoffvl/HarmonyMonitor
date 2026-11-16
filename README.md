# Harmony Monitor

A native iPhone app that reads live telemetry directly from a VESC Labs Harmony 16 over Bluetooth LE. The dashboard is configured for a 7S3P Molicel P50B pack.

| Pack specification | Value |
| --- | --- |
| Physical cells | 21 |
| Series groups | 7 |
| Nominal pack voltage | 25.2 V |
| Maximum charging voltage | 29.4 V |
| Nominal capacity | 15 Ah |
| Nominal energy | 378 Wh |

These are the pack specifications supplied for this project. The dashboard fills in measurements only after the BMS replies with a supported telemetry frame.

## Build and install

Follow the [Windows 11 to iPhone installation guide](Docs/Windows-Install.md). It covers GitHub upload, the Actions build, Apple Account signing with AltServer, Developer Mode, and seven-day renewal. The app targets iOS 17 or later and builds for arm64 on the device. The iPhone 17 Pro supports iOS 26. [Apple’s iOS compatibility list](https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/26)

If you have Xcode, open `HarmonyMonitor.xcodeproj` and select the shared **HarmonyMonitor** scheme. Choose an iPhone simulator and use **Product → Test** to run the tests. You can also test the protocol independently with Swift 6 or newer from the project root.

```sh
swift test
```

## Project structure

| Component | Function |
| --- | --- |
| `HarmonyCore/VESCPacketCodec.swift` | CRC-16, wire framing, and a streaming receive buffer for fragmented and coalesced BLE notifications |
| `HarmonyCore/VESCProtocol.swift` | Two read-only request types and bounds-checked firmware and battery telemetry decoding |
| `HarmonyCore/BMSDataModel.swift` | Firmware identity, series groups, temperature channels, current direction, and BMS-reported faults |
| `HarmonyMonitor/Bluetooth/BLEManager.swift` | CoreBluetooth scanning, explicit device selection, GATT discovery, subscriptions, and reconnection |
| `HarmonyMonitor/Bluetooth/TelemetryManager.swift` | Firmware identity check, foreground polling, response timeouts, freshness, and diagnostics |
| `HarmonyMonitor/Views/` | SwiftUI battery dashboard, seven series-group rows, discovery, diagnostics, and local preferences |
| `Tests/HarmonyCoreTests/` | XCTest vectors shared by Swift Package Manager and the hosted Xcode test target |
| `.github/workflows/build-ios.yml` | Simulator XCTest, arm64 iPhone build, and packaging as an IPA for later signing |

## Read-only operation

The app sends `COMM_FW_VERSION` and, after the connected device identifies as a Harmony 16, `COMM_BMS_GET_VALUES`. Both requests have empty argument lists. BLE notification subscriptions and any iOS pairing use standard transport operations. There are no configuration, balancing control, CAN forwarding, contactor, precharge, firmware upload, or raw command controls. Settings change only the app.

For the upstream UUIDs, field mapping, version requirements and unsupported cases, see [Protocol and firmware compatibility](Docs/Protocol.md). For the first connection, reading cross-checks and diagnostic export, see [Hardware check and troubleshooting](Docs/Hardware-Check.md).

## Verification

- The Linux Swift test run passed all 19 packet and telemetry tests. Test vectors were constructed from the documented upstream layout, with independently calculated CRCs.
- Swift files were parsed locally. The Xcode project, shared scheme, plist files, icon catalog and Actions workflow were structurally checked.
- The included workflow runs the Apple SDK build and simulator tests after you push the project to GitHub. Those steps and Windows-to-iPhone installation still need a first run. A physical iPhone and BMS were unavailable for testing.

The full project is distributed under [GPL-3.0-or-later](LICENSE). Upstream credits and source revisions are listed in the [protocol notes](Docs/Protocol.md).
