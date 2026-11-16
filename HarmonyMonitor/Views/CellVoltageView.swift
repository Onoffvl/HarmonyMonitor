// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct CellVoltageView: View {
    let values: BMSDataModel?
    @ScaledMetric(relativeTo: .subheadline) private var readingWidth: CGFloat = 97

    private var scale: ClosedRange<Int>? {
        guard let low = values?.lowest?.millivolts, let high = values?.highest?.millivolts else { return nil }
        let padding = max(10, (high - low) / 8)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        MonitorCard {
            Text("Series-group voltages").font(.headline)

            if let low = values?.lowest, let high = values?.highest, let spread = values?.spreadMillivolts {
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("Lowest · S\(low.id)", value: voltage(low.millivolts))
                    LabeledContent("Highest · S\(high.id)", value: voltage(high.millivolts))
                    LabeledContent("Difference", value: "\(spread) mV")
                }
                .font(.subheadline)
                .monospacedDigit()
                Divider()
            }

            ForEach(1...VESCProtocol.groupCount, id: \.self) { id in
                groupRow(id, values?.groups.first { $0.id == id }, scale: scale)
            }

            if let values {
                let active = values.groups.filter(\.balancing).map { "S\($0.id)" }
                LabeledContent("Balancing", value: active.isEmpty ? "Inactive" : active.joined(separator: ", "))
                    .font(.caption)
            }

            if let scale {
                LabeledContent("Bar scale", value: "\(voltage(scale.lowerBound)) to \(voltage(scale.upperBound))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func groupRow(_ id: Int, _ group: BMSDataModel.Group?, scale: ClosedRange<Int>?) -> some View {
        let reading = group.map { voltage($0.millivolts) } ?? "—"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                Text("S\(id)").font(.subheadline.weight(.semibold)).frame(width: 25, alignment: .leading)
                ReadingBar(fill: barFraction(group, scale: scale))
                    .frame(minWidth: 30)
                groupValue(reading, balancing: group?.balancing == true)
                    .frame(width: readingWidth, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 5) {
                LabeledContent {
                    groupValue(reading, balancing: group?.balancing == true)
                } label: {
                    Text("S\(id)").font(.subheadline.weight(.semibold))
                }
                ReadingBar(fill: barFraction(group, scale: scale))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Series group \(id)")
        .accessibilityValue(group.map { "\(reading), \($0.balancing ? "balancing" : "balancing off")" } ?? "Unavailable")
    }

    private func groupValue(_ reading: String, balancing: Bool) -> some View {
        HStack(spacing: 5) {
            if balancing {
                Image(systemName: "equal.circle.fill")
                    .foregroundStyle(MonitorTheme.amber)
                    .accessibilityLabel("Balancing")
            }
            Text(reading).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func barFraction(_ group: BMSDataModel.Group?, scale: ClosedRange<Int>?) -> Double? {
        guard let group, let scale else { return nil }
        return Double(group.millivolts - scale.lowerBound) / Double(scale.upperBound - scale.lowerBound)
    }

    private func voltage(_ millivolts: Int) -> String {
        let volts = Double(millivolts) / 1_000
        return "\(volts.formatted(.number.precision(.fractionLength(3)))) V"
    }
}
