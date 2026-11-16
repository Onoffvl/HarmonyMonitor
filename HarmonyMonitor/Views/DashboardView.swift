// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct DashboardView: View {
    let monitor: TelemetryManager
    @State private var showDevices = false
    @ScaledMetric(relativeTo: .largeTitle) private var socSize: CGFloat = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                connectionCard
                chargeCard
                electricalReadings
                CellVoltageView(values: monitor.telemetry)
                temperatureCard
                statusCard
                deviceCard
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(MonitorTheme.background.ignoresSafeArea())
        .navigationTitle("Harmony Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDevices) { DevicesView(monitor: monitor) }
    }

    private var connectionCard: some View {
        MonitorCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    connectionStatus
                    Spacer(minLength: 0)
                    connectionAction
                }
                VStack(alignment: .leading, spacing: 12) {
                    connectionStatus
                    connectionAction
                }
            }
            if let message = monitor.status.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if [.off, .denied, .unavailable].contains(monitor.bluetooth.radio) {
                Text(monitor.bluetooth.radio.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monitor.bluetooth.target?.name ?? "Harmony 16")
                .font(.headline)
            Label(connectionLabel, systemImage: connectionIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(connectionColor)
        }
    }

    @ViewBuilder
    private var connectionAction: some View {
        switch monitor.bluetooth.phase {
        case .disconnected:
            Button { showDevices = true } label: {
                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(MonitorTheme.green)
            .foregroundStyle(MonitorTheme.background)
        case .disconnecting:
            ProgressView().accessibilityLabel("Disconnecting")
        default:
            Button("Disconnect") { monitor.bluetooth.disconnect() }
                .buttonStyle(.bordered)
        }
    }

    private var connectionLabel: String {
        switch monitor.status {
        case .live: "Live telemetry"
        case .stale: "Telemetry stale"
        case .unavailable: "Data unavailable"
        case .diagnostics: "Diagnostics only"
        case .identifying: "Verifying device"
        case .waiting: "Connected · waiting for data"
        case .offline: monitor.bluetooth.phase.label
        }
    }

    private var connectionIcon: String {
        switch monitor.status {
        case .live: "dot.radiowaves.left.and.right"
        case .stale, .unavailable: "clock.badge.exclamationmark"
        case .diagnostics: "stethoscope"
        default: "circle"
        }
    }

    private var connectionColor: Color {
        switch monitor.status {
        case .live: MonitorTheme.green
        case .stale, .unavailable, .diagnostics: MonitorTheme.amber
        default: .secondary
        }
    }

    private var chargeCard: some View {
        let soc = monitor.telemetry?.stateOfCharge
        let flow = monitor.telemetry?.flow
        return MonitorCard(highlighted: true) {
            Text("State of charge")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    stateOfCharge(soc)
                    Spacer(minLength: 12)
                    if let flow { flowBadge(flow) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    stateOfCharge(soc)
                    if let flow { flowBadge(flow) }
                }
            }
            ReadingBar(fill: soc, height: 9)
        }
    }

    private func stateOfCharge(_ soc: Double?) -> some View {
        Text(soc?.formatted(.percent.precision(.fractionLength(1))) ?? "—")
            .font(.system(size: socSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .accessibilityLabel("State of charge")
            .accessibilityValue(soc?.formatted(.percent.precision(.fractionLength(1))) ?? "Unavailable")
    }

    private func flowBadge(_ flow: BMSDataModel.Flow) -> some View {
        let icon = switch flow {
        case .charging: "arrow.down.left"
        case .discharging: "arrow.up.right"
        case .idle: "pause.fill"
        }
        return Label(flow.rawValue, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(flow == .idle ? Color.secondary : MonitorTheme.green)
    }

    private var electricalReadings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                electricalMetric("Pack voltage", icon: "bolt", reading: monitor.telemetry?.packVoltage, unit: "V")
                electricalMetric("Pack current", icon: "arrow.left.arrow.right", reading: monitor.telemetry?.packCurrent, unit: "A")
            }
            VStack(spacing: 14) {
                electricalMetric("Pack voltage", icon: "bolt", reading: monitor.telemetry?.packVoltage, unit: "V")
                electricalMetric("Pack current", icon: "arrow.left.arrow.right", reading: monitor.telemetry?.packCurrent, unit: "A")
            }
        }
    }

    private func electricalMetric(_ title: String, icon: String, reading: Double?, unit: String) -> some View {
        let value = reading.map { "\($0.formatted(.number.precision(.fractionLength(2)))) \(unit)" } ?? "—"
        return MonitorCard {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    private var temperatureCard: some View {
        let temperatures = monitor.telemetry?.temperatures
        return MonitorCard {
            LabeledContent("Hottest cell temperature", value: monitor.temperatureUnit.reading(temperatures?.maximumCell))
                .font(.headline)
                .monospacedDigit()
            if let temperatures {
                temperatureRow("BMS IC", value: temperatures.ic)
                temperatureRow("Power switch", value: temperatures.mosfet)
                if let ambient = temperatures.ambient { temperatureRow("Ambient (T4)", value: ambient) }

                ForEach(temperatures.externalNTCs.indices, id: \.self) { index in
                    temperatureRow("Cell NTC \(index + 1)", value: temperatures.externalNTCs[index])
                }
                if temperatures.externalNTCs.isEmpty {
                    Text("No cell NTC channels reported.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func temperatureRow(_ title: String, value: Double?) -> some View {
        LabeledContent(title, value: monitor.temperatureUnit.reading(value))
            .font(.subheadline)
            .monospacedDigit()
    }

    private var statusCard: some View {
        MonitorCard {
            Text("BMS status").font(.headline)
            if let status = monitor.telemetry?.status {
                ForEach(status.faults, id: \.self) { fault in
                    Label(fault.title, systemImage: "exclamationmark.octagon.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MonitorTheme.red)
                }
                Text(status.raw)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            } else {
                Text("Unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deviceCard: some View {
        MonitorCard {
            LabeledContent("Pack", value: "7S3P · Molicel P50B")
            LabeledContent("Firmware", value: monitor.firmware?.versionLabel ?? "—")
            LabeledContent("Last successful update",
                           value: monitor.lastSuccessfulUpdate?.formatted(date: .abbreviated, time: .standard) ?? "—")
        }
        .font(.subheadline)
    }
}
