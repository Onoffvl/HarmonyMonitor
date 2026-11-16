# First connection and troubleshooting

## Check live readings

1. Power on or wake the Harmony 16 using its normal controls. Disconnect any existing monitoring client from BLE. Keep the phone nearby.
2. Open **Harmony Monitor → Diagnostics** and turn on **Capture raw notifications** for this first check. Go to **Battery → Connect**, allow Bluetooth and select the BMS by its advertised name. Complete the iOS pairing prompt using its existing PIN if asked.
3. The diagnostics log should show the VESC UART service, the TX notification subscription, a firmware reply for `VBMS16`, and an accepted BMS revision 1 with seven groups. On the dashboard, **Live telemetry** and the update time should appear after the first valid reply.
4. At rest, compare **Pack voltage** and **S1–S7** with the read-only **BMS** view of the desktop VESC Tool, or with existing pack measurements taken at the same time. If switching Bluetooth clients, disconnect between checks. Confirm that the displayed difference in mV equals the highest minus the lowest of the seven values. A 7S3P pack still has only seven independently monitored voltages. If a normal charge or load is already running, verify negative current during charging and positive current during discharge.
5. Tap **Disconnect**. The dashboard should clear measurement values and retain a labelled **Last successful update** timestamp. Reconnect, then background the app and reopen it to check automatic reconnection if enabled. Switch off raw capture after the check.

## Diagnose a missing reading

| Symptom | Check |
| --- | --- |
| Bluetooth permission denied | Open **iPhone Settings → Privacy & Security → Bluetooth** and enable Harmony Monitor. Then reopen the scanner. |
| BMS absent from the scan | Check that it is awake, within range and available to a new client. Toggle **Show other Bluetooth devices** and scan again. If you see the known BMS name under the expanded list, choose **Connect as Harmony 16**. |
| The app can connect but the UART service is missing | Expand the BLE service list in **Diagnostics**. Use **Inspect BLE services** from the device list for a passive connection. Choose **Listen** on an exposed notification or indication characteristic to capture raw bytes. Compatibility with a different service requires a verified specification or device capture. |
| Notification setup fails or reports authentication | Check for an iOS pairing prompt and use the BMS’s existing BLE PIN if required. Disconnect, close any other client and retry. |
| Firmware query times out or the device is unrecognized | Check the UART UUIDs and capture the first notifications after reconnecting. The app requires a matching `VBMS16` custom-module identity before starting command-96 polling. |
| Wrong series-group count or unsupported data version | Copy the log and the raw reply. The dashboard expects seven groups and the status-bearing revision-1 layout. Review the fields in the existing BMS telemetry without changing its settings. |
| Temperature shows a dash | Check the configured cell NTCs in the BMS reporting. With no cell NTCs or a sensor sentinel, the app shows an unavailable reading. |
| Telemetry becomes stale while BLE still says connected | The transport may still be up when packets time out or fail CRC. Check the error log, then disconnect and retry nearby. At the 1 s setting the live values expire after four seconds without a valid reading. |

## Export a useful capture

In **Diagnostics**, enable **Capture raw notifications**, reconnect, and wait for about ten seconds or one clear error. Open the log actions menu and choose **Copy log** or **Share log**. Include the iOS version, displayed firmware identity if available, whether iOS requested pairing, and what the dashboard showed. The log can include the advertised name, local Bluetooth identifier and raw firmware reply bytes, so review it before sharing.
