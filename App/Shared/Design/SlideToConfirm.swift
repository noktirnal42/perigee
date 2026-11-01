import SwiftUI

/// "Slide to reboot": destructive actions only fire once the thumb reaches the end of the track.
struct SlideToConfirm: View {
    let label: String
    var tint: Color = Theme.bad
    let action: () async -> Void

    @State private var offset: CGFloat = 0
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let thumb: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - thumb - 8)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
                Capsule().fill(tint.opacity(0.35)).frame(width: offset + thumb + 4)
                Text(busy ? "Working…" : label)
                    .font(.system(.body, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity).opacity(1 - Double(offset / travel))
                Circle().fill(.white).frame(width: thumb, height: thumb)
                    .overlay(Image(systemName: busy ? "hourglass" : "chevron.right.2").foregroundStyle(.black).font(.headline))
                    .padding(4).offset(x: offset)
                    .gesture(DragGesture()
                        .onChanged { g in guard !busy else { return }; offset = min(max(0, g.translation.width), travel) }
                        .onEnded { _ in
                            guard !busy else { return }
                            if offset > travel * 0.92 {
                                busy = true; Haptics.warning()
                                Task { await action(); busy = false; withAnimation(reduceMotion ? nil : .spring) { offset = 0 } }
                            } else { withAnimation(reduceMotion ? nil : .spring) { offset = 0 } }
                        })
            }
        }
        .frame(height: thumb + 8)
        // VoiceOver can't drag, so expose the action directly with an explicit "activate" confirmation semantics.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Double tap to perform this action. It is destructive.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { busy = true; await action(); busy = false } }
    }
}
