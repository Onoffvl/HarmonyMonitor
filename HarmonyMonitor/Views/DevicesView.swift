// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

struct DevicesView: View {
    let monitor: TelemetryManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showOtherDevices = false

    private var bluetooth: BLEManager { monitor.bluetooth }

    var body: some View {
        NavigationStack {
            List {
                Section("VESC UART") {
                    let devices = sortedDevices.filter(\.advertisesUART)
                    if devices.isEmpty {
                        if bluetooth.isScanning {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Scanning nearby devices")
                            }
                        } else {
                            Text(bluetooth.radio == .ready ? "No VESC UART devices found." : bluetooth.radio.message)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(devices) { device in
                        Button { choose(device, intent: .monitor) } label: { deviceRow(device) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Inspect BLE services") { choose(device, intent: .inspect) }
                            }
                    }
                }
                if bluetooth.radio == .ready {
                    Section {
                        Toggle("Show other Bluetooth devices", isOn: $showOtherDevices)
                        if showOtherDevices {
                            let others = sortedDevices.filter { !$0.advertisesUART }
                            ForEach(others) { device in
                                Menu {
                                    Button("Connect as Harmony 16") { choose(device, intent: .monitor) }
                                    Button("Inspect BLE services") { choose(device, intent: .inspect) }
                                } label: {
                                    deviceRow(device)
                                }
                            }
                        }
                    } footer: {
                        Text("Some firmware may omit the UART service from its advertisement.")
                    }
                }
                if bluetooth.radio == .denied {
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            .navigationTitle("Bluetooth devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan again") { bluetooth.startScan() }
                        .disabled(bluetooth.isScanning || bluetooth.radio != .ready)
                }
            }
        }
        .onAppear { bluetooth.startScan() }
        .onDisappear { bluetooth.stopScan() }
    }

    private var sortedDevices: [BLEManager.Device] {
        bluetooth.devices.sorted {
            let lhs = $0.rssi ?? Int.min
            let rhs = $1.rssi ?? Int.min
            return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs > rhs
        }
    }

    private func deviceRow(_ device: BLEManager.Device) -> some View {
        HStack {
            Image(systemName: device.advertisesUART ? "battery.75percent" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(MonitorTheme.green)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).foregroundStyle(.primary)
                Text(device.id.uuidString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let rssi = device.rssi {
                Text("\(rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func choose(_ device: BLEManager.Device, intent: BLEManager.Intent) {
        monitor.connect(device, intent: intent)
        dismiss()
    }
}
