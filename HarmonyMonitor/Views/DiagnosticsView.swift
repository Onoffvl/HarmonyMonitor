// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Bindable var monitor: TelemetryManager
    @State private var copied = false

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("BLE link", value: monitor.bluetooth.phase.label)
                if let device = monitor.bluetooth.target {
                    LabeledContent("Device", value: device.name)
                    Text(device.id.uuidString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let firmware = monitor.firmware {
                    LabeledContent("Hardware", value: firmware.hardwareName)
                    LabeledContent("Firmware", value: firmware.versionLabel)
                    if let name = firmware.firmwareName, !name.isEmpty {
                        LabeledContent("Firmware name", value: name)
                    }
                }
                Toggle("Capture raw notifications", isOn: $monitor.captureRawNotifications)
            }

            Section {
                if monitor.bluetooth.services.isEmpty {
                    Text("No services discovered.")
                        .foregroundStyle(.secondary)
                }
                ForEach(monitor.bluetooth.services) { service in
                    serviceRow(service)
                }
            } header: {
                Text("BLE services")
            } footer: {
                Text("Listen captures notifications from the selected characteristic.")
            }

            Section {
                if monitor.logs.isEmpty {
                    Text("No connection events yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(monitor.logs.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.time, format: .dateTime.hour().minute().second())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("Connection and packet log")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Copy log", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = monitor.exportLogs()
                        copied = true
                    }
                    ShareLink(item: monitor.exportLogs()) { Label("Share log", systemImage: "square.and.arrow.up") }
                    Button("Clear log", systemImage: "trash", role: .destructive) { monitor.clearLogs() }
                } label: {
                    Label("Log actions", systemImage: "ellipsis.circle")
                }
                .disabled(monitor.logs.isEmpty)
            }
        }
        .alert("Log copied", isPresented: $copied) { Button("OK", role: .cancel) {} }
    }

    private func serviceRow(_ service: BLEManager.Service) -> some View {
        DisclosureGroup {
            if service.characteristics.isEmpty {
                Text("No characteristics discovered.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(service.characteristics) { characteristic in
                VStack(alignment: .leading, spacing: 5) {
                    Text(characteristic.uuid)
                        .textSelection(.enabled)
                        .font(.system(.caption, design: .monospaced))
                    Text(characteristic.properties)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if characteristic.canListen {
                        Button(characteristic.isNotifying ? "Stop listening" : "Listen") {
                            monitor.listenForDiagnostics(!characteristic.isNotifying, on: characteristic)
                        }
                        .buttonStyle(.bordered)
                        .disabled(characteristic.changingSubscription)
                    } else if characteristic.isNotifying {
                        Label("Notifications enabled", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(MonitorTheme.green)
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Text(service.uuid)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
