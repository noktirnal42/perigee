import SwiftUI
import StarlinkKit

/// Rounded dark translucent card. Uses Liquid Glass where the OS has it, a material elsewhere.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.radius
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content.background(Theme.deep, in: shape).overlay(shape.strokeBorder(Theme.cardStroke))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint((tint ?? .black).opacity(0.28)), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? .black).opacity(0.25), in: shape)
                .overlay(shape.strokeBorder(Theme.cardStroke))
        }
    }
}

extension View {
    /// Tab screens draw their own wide-type headers, so the system bar is hidden on iOS.
    func customHeader() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
    func card(radius: CGFloat = Theme.radius, tint: Color? = nil) -> some View { modifier(CardBackground(radius: radius, tint: tint)) }
}

/// Full-screen backdrop for content screens: void black with a faint ember horizon glow.
struct ScreenBackground: View {
    var intensity: Double = 1
    var body: some View {
        ZStack {
            Theme.void
            RadialGradient(colors: [Theme.emberDeep.opacity(0.55 * intensity), .clear], center: .init(x: 0.85, y: -0.05),
                           startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Theme.info.opacity(0.10 * intensity), .clear], center: .init(x: 0.05, y: 1.0),
                           startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: AnyView? = nil
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack { Text(text).eyebrow(); Spacer(); trailing }
            .padding(.horizontal, 4).padding(.top, 8).accessibilityAddTraits(.isHeader)
    }
}

/// White-pill segmented control, like the official app's Devices / Nodes switch.
struct PillPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let on = value == selection
                Button {
                    Haptics.select()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(.subheadline, weight: .semibold))
                        .padding(.vertical, 9).padding(.horizontal, 14).frame(maxWidth: .infinity)
                        .foregroundStyle(on ? Color.black : Color.white.opacity(0.75))
                        .background { if on { Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: ns) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4).background(Color.white.opacity(0.09), in: Capsule())
    }
}

struct StatusChip: View {
    let text: String
    var color: Color = Theme.good
    var pulse = false
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.9), radius: pulse && on ? 7 : 2)
            Text(text).font(.system(.footnote, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
        .onAppear {
            guard pulse, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BandBadge: View {
    let band: RadioBand
    var body: some View {
        Text(band.label)
            .font(.system(.caption2, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.22), in: Capsule()).foregroundStyle(color)
            .accessibilityLabel("\(band.label) band")
    }
    private var color: Color { band == .ghz2 ? Theme.warn : band == .ethernet ? Theme.signal : Theme.info }
}

struct HealthDot: View {
    let health: Health
    var body: some View { Circle().fill(Theme.color(for: health)).frame(width: 9, height: 9).accessibilityHidden(true) }
}

/// A toggle with a short plain-language explanation underneath, as in the official app's settings.
struct ExplainedToggle: View {
    let title: String
    let explanation: String
    @Binding var isOn: Bool
    var disabled = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) { Text(title).font(.body.weight(.medium)) }.toggleStyle(.switch).tint(Theme.ember).disabled(disabled)
            Text(explanation).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4).accessibilityElement(children: .contain)
    }
}

enum Haptics {
    static func select() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    static func impact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
