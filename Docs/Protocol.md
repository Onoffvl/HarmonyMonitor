# Protocol and firmware compatibility

## Source trail

VESC Labs lists Bluetooth as a supported interface for the Harmony 16, and the datasheet lists a range of 4 to 16 series groups. VESC Tool publishes the standard BLE UART UUIDs, transaction IDs and receiving layout. The Harmony package publishes board values to the VESC BMS state. VESC Express contains the `VBMS16` board definition, the BLE UART endpoint and the on-device serializers. The `bldc` BMS command is a useful cross-check of the wire layout and can expose CAN-sourced BMS data on a motor controller. Harmony Monitor checks the identity of the direct BLE peripheral before it requests battery values. [VESC Labs downloads](https://www.vesclabs.com/downloads/) · [Harmony 16 datasheet](https://usercontent.one/wp/www.vesclabs.com/wp-content/uploads/2025/09/vesc_harmony_16_datasheet.pdf?media=1761239595) · [VESC Tool](https://github.com/vedderb/vesc_tool) · [VESC packages](https://github.com/vedderb/vesc_pkg) · [VESC motor firmware](https://github.com/vedderb/bldc) · [VESC Express](https://github.com/vedderb/vesc_express)

| Implementation evidence | Source revision and files |
| --- | --- |
| Phone and desktop BLE transport, command IDs and reference decoder | VESC Tool `f1b5a5262730` · [bleuart.cpp](https://github.com/vedderb/vesc_tool/blob/f1b5a526273005c36eb52bac1c03d7ec66ba6744/bleuart.cpp) · [commands.cpp](https://github.com/vedderb/vesc_tool/blob/f1b5a526273005c36eb52bac1c03d7ec66ba6744/commands.cpp) · [datatypes.h](https://github.com/vedderb/vesc_tool/blob/f1b5a526273005c36eb52bac1c03d7ec66ba6744/datatypes.h) |
| Board target and Bluetooth endpoint | VESC Express `9ed29f0f99e6` · [VBMS16 board header](https://github.com/vedderb/vesc_express/blob/9ed29f0f99e670501583f16f7f68b1cea9ed3889/main/hwconf/vesc/vbms16/hw_vbms16.h) · [board measurements](https://github.com/vedderb/vesc_express/blob/9ed29f0f99e670501583f16f7f68b1cea9ed3889/main/hwconf/vesc/vbms16/hw_vbms16.c) · [comm_ble.c](https://github.com/vedderb/vesc_express/blob/9ed29f0f99e670501583f16f7f68b1cea9ed3889/main/comm_ble.c) |
| Framing and wire-side command handlers | VESC Express `9ed29f0f99e6` · [packet.c](https://github.com/vedderb/vesc_express/blob/9ed29f0f99e670501583f16f7f68b1cea9ed3889/main/packet.c) · [commands.c](https://github.com/vedderb/vesc_express/blob/9ed29f0f99e670501583f16f7f68b1cea9ed3889/main/commands.c) · [bms.c](https://github.com/vedderb/vesc_express/blob/9ed29f0f99e670501583f16f7f68b1cea9ed3889/main/bms.c) |
| Harmony device matching, shunt current sign, sensor slots and status tokens | Harmony 16 package v1.0.1 in VESC Packages `4cb7711f3039` · [pkgdesc.qml](https://github.com/vedderb/vesc_pkg/blob/4cb7711f30394f4a0658b1e8481888d4cf2bc9b4/vbms_harmony16/pkgdesc.qml) · [harmony16.lisp](https://github.com/vedderb/vesc_pkg/blob/4cb7711f30394f4a0658b1e8481888d4cf2bc9b4/vbms_harmony16/harmony16.lisp) |
| Motor-controller BMS packet cross-check | `bldc` `cb79df8960f7` · [bms.c](https://github.com/vedderb/bldc/blob/cb79df8960f77fcdf368f3b921d24d5a3ed86345/bms.c) |

## BLE transport

The onboard ESP32 provides the VESC BLE UART service. The characteristic names below are from the BMS peripheral’s perspective. The phone writes to RX and subscribes to TX. The app prefers write-with-response when advertised and also supports write-without-response. It waits for the TX subscription to succeed before sending the first request. [VESC Tool BLE transport](https://github.com/vedderb/vesc_tool/blob/master/bleuart.cpp) · [VESC Express BLE endpoint](https://github.com/vedderb/vesc_express/blob/main/main/comm_ble.c)

| Role | UUID |
| --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| Peripheral RX, phone writes | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| Peripheral TX, phone subscribes | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

The application protocol is a byte stream. BLE notification boundaries can split or combine frames. A VESC frame has a start byte of 2, 3 or 4, followed by 1, 2 or 3 big-endian length bytes respectively. The length covers the payload. The payload is followed by a big-endian CRC-16/XMODEM and the stop byte `03`. The CRC covers the payload with polynomial `0x1021` and initial value zero. The app’s BLE decoder uses the VESC Express default 512-byte payload limit. [Upstream framing](https://github.com/vedderb/vesc_express/blob/main/main/packet.c) · [Default payload cap](https://github.com/vedderb/vesc_express/blob/main/main/packet.h)

| Request | ID | Complete request frame in hex |
| --- | --- | --- |
| `COMM_FW_VERSION` | 0 | `02 01 00 00 00 03` |
| `COMM_BMS_GET_VALUES` | 96 | `02 01 60 6C A6 03` |

The firmware handler returns its major and minor version, NUL-terminated board name and identity fields. The app requires board name `VBMS16` and hardware type 2 (custom module). The optional firmware name may be `harmony` or empty, matching the official package rule. This is the ESP32/VESC firmware version. The query has no Harmony package version or BQ monitor-chip revision field. The BMS query receives a standard command-96 response directly from the local BMS state. There is no Harmony-specific telemetry request or wake/configuration command in the app. [VESC Express command handler](https://github.com/vedderb/vesc_express/blob/main/main/commands.c) · [Package identity rule](https://github.com/vedderb/vesc_pkg/blob/main/vbms_harmony16/pkgdesc.qml)

## Command 96 response

The first byte is the command ID. Offset and length depend on the series group and temperature channel counts. Integer fields are big-endian. The Swift reader bounds-checks each read.

| Field order after ID | Wire encoding | App interpretation |
| --- | --- | --- |
| Pack voltage, charger voltage | Two signed 32-bit values, ÷ 10⁶ V | Pack voltage comes from `v_tot`, which the Harmony package populates with the sum of the cell-group measurements. |
| Forwarded current, local shunt current | Two signed 32-bit values, ÷ 10⁶ A | Pack current comes from `i_in_ic`, the local BMS shunt. Current is positive on discharge and negative on charge. The dashboard labels readings strictly within ±0.10 A as idle. |
| Ah and Wh counters | Two signed 32-bit values, ÷ 10³ | Skipped by the app. |
| Series-group count, group voltages | One count byte, then that many signed 16-bit mV values | Requires seven groups. S1–S7 each represent one parallel group. The minimum, maximum and mV difference are calculated from these seven BMS measurements. |
| Balancing flags | One byte per group | A reported 1 marks that group as balancing. |
| Temperature-channel count and readings | One count byte, then signed 16-bit values ÷ 10² °C | Slots 0–4 are IC, lowest cell, highest cell, power switch and ambient. Slots 5–8 carry the configured cell NTCs in order, if present. |
| IC temperature, humidity-sensor temperature, humidity, highest cell temperature | Four signed 16-bit fields, ÷ 10² | The app uses IC temperature and the reported highest cell temperature. |
| SoC, SoH | Two signed 16-bit values, ÷ 10³ | SoC is shown as a percentage for values in 0–1. Harmony package v1.0.1 sets SoH to a constant, so the dashboard omits it. |
| CAN ID, lifetime charge and discharge counters, pressure | One byte, four VESC auto-float 32-bit fields, one signed 16-bit field | Skipped by the app. |
| Data revision, status | One byte, then NUL-terminated status text | Supports revision 1 and up to 40 status characters. The app displays status text and identifies the four verified fault tokens below. |

The installed Harmony package decides whether SoC uses coulomb counting or a voltage estimate. The app displays that result. With no cell NTCs configured, the package’s highest cell value can be a 24 °C fallback. The app leaves the cell temperature blank in that case. Board firmware uses −1 °C for a failed NTC conversion, so that exact NTC reading is treated as unavailable. The package also uses −300 °C for unavailable ambient T4. [On-wire serialization](https://github.com/vedderb/vesc_express/blob/main/main/bms.c) · [Harmony telemetry producer](https://github.com/vedderb/vesc_pkg/blob/main/vbms_harmony16/harmony16.lisp) · [NTC conversion](https://github.com/vedderb/vesc_express/blob/main/main/hwconf/vesc/vbms16/hw_vbms16.c)

| Reported fault token | Dashboard label |
| --- | --- |
| `FLT_PSW_SHORT` | Power switch short circuit |
| `FLT_PSW_OT` | Power switch overtemperature |
| `FLT_PCHG` | Precharge fault |
| `FLT_CHG_OC` | Charge overcurrent |

Revision 1 carries status text without a separate severity field. Unknown tokens appear as reported text. A blank status appears as unavailable. Red appears for the verified fault tokens above. [Harmony status producer](https://github.com/vedderb/vesc_pkg/blob/main/vbms_harmony16/harmony16.lisp)

## Compatibility boundaries

- The app requires the UART GATT service and its verified characteristics, a matching firmware identity, and a revision-1 frame with seven series groups, five to nine temperature slots and the full status-bearing layout. Older VESC Tool decoders allow truncated optional tails. Harmony Monitor requires the revision byte and complete status field so unverified layouts stay in diagnostics.
- VESC Express supports open, encrypted and disabled Bluetooth modes. With encrypted BLE, complete the iOS pairing prompt using the BMS’s existing PIN. A sleeping unit, disabled BLE or a custom BLE configuration can prevent UART advertising or service discovery. Passive inspection exposes available GATT services and can record notifications from a characteristic you select.
- The firmware serializer returns stored BMS values without a per-sample timestamp. Track freshness from the last successfully decoded phone-side reply. The dashboard clears live numbers on link loss, an invalid telemetry reply, or expiry. At the 1 s setting, expiry is four seconds after the last valid reply.
- The app disconnects in the background. An active BLE connection can keep the BMS awake according to the package’s sleep logic.
- Published source establishes the protocol and decoder limits above. It does not establish a release-by-release compatibility matrix for retail firmware, or identify the firmware installed on your specific unit. Use the [hardware check](Hardware-Check.md) to record the reported firmware and payload from your BMS. [VESC Express BLE modes](https://github.com/vedderb/vesc_express/blob/main/main/comm_ble.c) · [Package sleep behavior and data revision](https://github.com/vedderb/vesc_pkg/blob/main/vbms_harmony16/harmony16.lisp)

The Swift framing and protocol implementation references GPL-covered VESC Tool and VESC Express code by Benjamin Vedder and contributors. The telemetry mapping references the official Harmony 16 package. The corresponding Swift source and the [GNU General Public License version 3](../LICENSE) are included in this project.
