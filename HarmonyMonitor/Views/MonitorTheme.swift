// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

enum MonitorTheme {
    static let background = adaptive(dark: 0x0A1112, light: 0xF1F5F4)
    static let surface = adaptive(dark: 0x142021, light: 0xFFFFFF)
    static let track = adaptive(dark: 0x2B3C3D, light: 0xD7E4E1)
    static let accentSurface = adaptive(dark: 0x102E27, light: 0xE4F3EC)
    static let green = adaptive(dark: 0x70E3AA, light: 0x11714C)
    static let amber = adaptive(dark: 0xF2C57A, light: 0x83540A)
    static let red = adaptive(dark: 0xFF9F9F, light: 0xA3232B)

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct MonitorCard<Content: View>: View {
    let highlighted: Bool
    private let content: Content

    init(highlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.highlighted = highlighted
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(highlighted ? MonitorTheme.accentSurface : MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ReadingBar: View {
    let fill: Double?
    var height: CGFloat = 7
    var color = MonitorTheme.green

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MonitorTheme.track)
                if let fill {
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * CGFloat(min(max(fill, 0), 1)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
