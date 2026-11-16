// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

enum MonitorAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

@main
@MainActor
struct HarmonyMonitorApp: App {
    @State private var monitor = TelemetryManager()
    @AppStorage("appearance") private var appearance: MonitorAppearance = .dark
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { DashboardView(monitor: monitor) }
                    .tabItem { Label("Battery", systemImage: "battery.75percent") }
                NavigationStack { DiagnosticsView(monitor: monitor) }
                    .tabItem { Label("Diagnostics", systemImage: "waveform.path") }
                NavigationStack { SettingsView(monitor: monitor, appearance: $appearance) }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(MonitorTheme.green)
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { monitor.setForeground(true) }
                if phase == .background { monitor.setForeground(false) }
            }
        }
    }
}
