import SwiftUI
import AppKit

/// Glade's look: the same plum, paper and peach as Hoot and the website.
/// Square corners and hard offset shadows keep everything on a pixel grid.
enum Theme {
    static let ink = Color(hex: 0x2A1A26)          // window background
    static let deep = Color(hex: 0x1F1320)         // content area, a step darker than the sidebar
    static let surface = Color(hex: 0x33202E)      // cards
    static let surfaceHi = Color(hex: 0x432A3C)    // hovered / raised
    static let outline = Color(hex: 0x3B2230)
    static let line = Color(hex: 0x5A3A52)         // card borders
    static let paper = Color(hex: 0xFFF4DC)
    static let peach = Color(hex: 0xFFD9B8)
    static let sprout = Color(hex: 0x5DC46A)
    static let teal = Color(hex: 0x2BA89A)
    static let sparkle = Color(hex: 0xFFD23F)
    static let alert = Color(hex: 0xFF6B7F)

    static var secondary: Color { paper.opacity(0.74) }   // 4.5:1+ on surface and deep

    static func title(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func voice(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
}

/// A square card with a hard pixel shadow, like the cards on the website.
struct PixelCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
            .background(Rectangle().fill(Color.black.opacity(0.35)).offset(x: 4, y: 4))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(Theme.outline)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.sparkle.opacity(enabled ? 1 : 0.35))
            .overlay(Rectangle().stroke(Theme.outline, lineWidth: 2))
            .background(Rectangle().fill(Color.black.opacity(0.4)).offset(x: 3, y: configuration.isPressed ? 0 : 3))
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .opacity(enabled ? 1 : 0.7)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.paper.opacity(enabled ? 1 : 0.45))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.surfaceHi : Theme.ink)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
    }
}

/// A square on/off switch: sprout when on.
struct PixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Rectangle().fill(configuration.isOn ? Theme.sprout : Theme.ink)
                    Rectangle().fill(Theme.paper).frame(width: 16, height: 16).padding(3)
                }
                .frame(width: 44, height: 24)
                .overlay(Rectangle().stroke(configuration.isOn ? Theme.outline : Theme.line, lineWidth: 2))
                configuration.label
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Theme.paper)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// Page header: big rounded title with one line of context under it.
struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.title()).foregroundColor(Theme.paper)
            Text(subtitle).font(.system(size: 13)).foregroundColor(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Hoot, idling: the same sprite code as the pop-up, drawn at an integer pixel scale.
struct MiniHoot: View {
    var scale: CGFloat = 4
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: reduceMotion)) { tl in
            let sprite = makeSprite(hoot: .calm, t: reduceMotion ? 0.4 : tl.date.timeIntervalSinceReferenceDate)
            Canvas { ctx, _ in
                for y in 0..<32 {
                    var x = 0
                    while x < 32 {
                        let c = sprite.px[y * 32 + x]
                        if c == 0 { x += 1; continue }
                        var e = x
                        while e < 32, sprite.px[y * 32 + e] == c { e += 1 }
                        ctx.fill(Path(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: CGFloat(e - x) * scale, height: scale)),
                                 with: .color(palette[Int(c)]))
                        x = e
                    }
                }
            }
            .frame(width: 32 * scale, height: 32 * scale)
        }
        .accessibilityLabel("Hoot")
    }
}

/// − value + in square buttons, matching the rest of the window.
struct PixelStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit = "s"
    var zeroLabel: String? = nil
    let label: String

    private func bump(_ delta: Double) { value = min(range.upperBound, max(range.lowerBound, value + delta)) }

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) { bump(-step) }
            Text(value == 0 ? (zeroLabel ?? "0 \(unit)") : "\(Int(value)) \(unit)")
                .font(Theme.voice(12)).foregroundColor(Theme.paper)
                .frame(width: 64, height: 26)
                .background(Theme.ink)
                .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
            button("plus", enabled: value < range.upperBound) { bump(step) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value == 0 ? (zeroLabel ?? "0 \(unit)") : "\(Int(value)) \(unit)")
        .accessibilityAdjustableAction { dir in bump(dir == .increment ? step : -step) }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .heavy))
                .foregroundColor(Theme.paper.opacity(enabled ? 1 : 0.35))
                .frame(width: 26, height: 26)
                .background(Theme.surfaceHi)
                .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
