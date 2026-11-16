// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct SettingsView: View {
    @Bindable var monitor: TelemetryManager
    @Binding var appearance: MonitorAppearance

    var body: some View {
        Form {
            Section("Display") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(MonitorAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Temperature unit", selection: $monitor.temperatureUnit) {
                    ForEach(TelemetryManager.TemperatureUnit.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section {
                Picker("Update interval", selection: $monitor.refreshRate) {
                    ForEach(TelemetryManager.RefreshRate.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Automatically reconnect", isOn: $monitor.autoReconnect)
            } header: {
                Text("Bluetooth")
            } footer: {
                Text("Monitoring runs in the foreground. These settings are stored on your iPhone.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
