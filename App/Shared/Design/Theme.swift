import SwiftUI
import StarlinkKit

/// Perigee's design tokens. Dark-first: near-black base, ember (Mars) warmth, signal-white beams.
enum Theme {
    // Surfaces
    static let void = Color(red: 0.020, green: 0.027, blue: 0.039)         // #05070A
    static let deep = Color(red: 0.055, green: 0.063, blue: 0.082)
    static let card = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.11)

    // Brand
    static let ember = Color(red: 1.00, green: 0.42, blue: 0.24)          // #FF6B3D
    static let emberDeep = Color(red: 0.62, green: 0.18, blue: 0.10)
    static let dust = Color(red: 0.94, green: 0.62, blue: 0.40)
    static let signal = Color(red: 0.86, green: 0.95, blue: 1.00)         // beam white-blue

    // Semantic
    static let good = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let warn = Color(red: 1.00, green: 0.75, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.31, blue: 0.32)
    static let info = Color(red: 0.42, green: 0.74, blue: 1.00)

    static func color(for h: Health) -> Color {
        switch h { case .good: good; case .fair: warn; case .poor: bad; case .unknown: Color.white.opacity(0.4) }
    }

    static let radius: CGFloat = 22
    static let spacing: CGFloat = 16
}

/// Wide geometric sans, echoing the wordmark style of space-industry branding without copying any of it.
extension Font {
    static func wide(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default).width(.expanded)
    }
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// Section/caption style used for small uppercase labels.
    func eyebrow() -> some View {
        self.font(.system(.caption2, design: .default, weight: .semibold).width(.expanded))
            .textCase(.uppercase).tracking(1.4).foregroundStyle(.secondary)
    }
}
