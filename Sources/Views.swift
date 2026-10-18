import SwiftUI
import AppKit

let winW: CGFloat = 290
let winH: CGFloat = 400
let spriteScale: CGFloat = 6
let spriteSize: CGFloat = 192
let rightPad: CGFloat = 12

final class BuddyModel: ObservableObject {
    @Published var visible = false
    @Published var kind: Mood = .waiting
    @Published var message = ""
    @Published var project = ""
    @Published var shownAt = Date()
    @Published var phaseStart = Date()
    @Published var exitStart: Date? = nil
    @Published var ageOffset: Double = 0
    @Published var look = 0
    var bubbleRect: CGRect = .zero
    var onActivate: () -> Void = {}
    var onDismiss: () -> Void = {}
}

// MARK: keyframes

struct Key { let t: Double; let dy: Double; let sx: Double; let sy: Double }

func sampleKeys(_ keys: [Key], _ t: Double) -> (dy: Double, sx: Double, sy: Double) {
    guard let first = keys.first, let last = keys.last else { return (0, 1, 1) }
    if t <= first.t { return (first.dy, first.sx, first.sy) }
    if t >= last.t { return (last.dy, last.sx, last.sy) }
    var i = 0
    while keys[i + 1].t < t { i += 1 }
    let a = keys[i], b = keys[i + 1]
    let x = (t - a.t) / (b.t - a.t)
    let u = x * x * (3 - 2 * x)
    return (a.dy + (b.dy - a.dy) * u, a.sx + (b.sx - a.sx) * u, a.sy + (b.sy - a.sy) * u)
}

let enterKeys = [
    Key(t: 0.00, dy: 240, sx: 0.90, sy: 1.15),
    Key(t: 0.26, dy: -16, sx: 0.88, sy: 1.22),
    Key(t: 0.38, dy: 0, sx: 1.24, sy: 0.72),
    Key(t: 0.52, dy: -8, sx: 0.92, sy: 1.10),
    Key(t: 0.64, dy: 0, sx: 1.08, sy: 0.92),
    Key(t: 0.82, dy: 0, sx: 1, sy: 1),
]
let exitKeys = [
    Key(t: 0.00, dy: 0, sx: 1, sy: 1),
    Key(t: 0.14, dy: 0, sx: 1.16, sy: 0.80),
    Key(t: 0.34, dy: -46, sx: 0.88, sy: 1.18),
    Key(t: 0.70, dy: 260, sx: 0.9, sy: 1.2),
]
let exitDuration = 0.72

// MARK: bubble

struct PixelBubble: Shape {
    var tailX: CGFloat
    func path(in r: CGRect) -> Path {
        let n: CGFloat = 4, tail: CGFloat = 12
        let bottom = r.maxY - tail
        var p = Path()
        p.move(to: CGPoint(x: r.minX + n, y: r.minY))
        for pt in [
            (r.maxX - n, r.minY), (r.maxX - n, r.minY + n), (r.maxX, r.minY + n),
            (r.maxX, bottom - n), (r.maxX - n, bottom - n), (r.maxX - n, bottom),
            (tailX + 12, bottom), (tailX + 12, bottom + 4), (tailX + 8, bottom + 4), (tailX + 8, bottom + 8),
            (tailX + 4, bottom + 8), (tailX + 4, bottom + 12), (tailX - 4, bottom + 12), (tailX - 4, bottom + 8),
            (tailX - 8, bottom + 8), (tailX - 8, bottom + 4), (tailX - 12, bottom + 4), (tailX - 12, bottom),
            (r.minX + n, bottom), (r.minX + n, bottom - n), (r.minX, bottom - n), (r.minX, r.minY + n), (r.minX + n, r.minY + n),
        ] { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        p.closeSubpath()
        return p
    }
}

private struct RectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

let inkColor = Color(hex: 0x3d2236)
let creamColor = Color(hex: 0xfff6dc)

struct BubbleView: View {
    let title: String
    let message: String
    let project: String
    let chars: Int
    let tier: Int
    let onClose: () -> Void

    static let width: CGFloat = 250
    static var tailX: CGFloat { width - spriteSize / 2 - 4 }

    func reveal(_ s: String, from: Int) -> String { String(s.prefix(max(0, chars - from))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(reveal(title, from: 0))
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(tier == 2 ? Color(hex: 0xc2203a) : inkColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onClose) {
                    Text("x")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(inkColor)
                        .frame(width: 16, height: 16)
                        .background(Color(hex: 0xffd9b8))
                        .overlay(Rectangle().stroke(inkColor, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            if !message.isEmpty {
                Text(reveal(message, from: title.count))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(inkColor.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !project.isEmpty, chars > title.count + message.count {
                Text("> " + project)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(hex: 0x2fa89b))
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 10 + 12)
        .frame(width: Self.width, alignment: .leading)
        .background(
            ZStack {
                PixelBubble(tailX: Self.tailX).fill(inkColor.opacity(0.9)).offset(x: 3, y: 3)
                PixelBubble(tailX: Self.tailX).fill(creamColor)
                PixelBubble(tailX: Self.tailX).stroke(inkColor, style: StrokeStyle(lineWidth: 3, lineJoin: .miter))
            }
        )
        .background(GeometryReader { g in Color.clear.preference(key: RectKey.self, value: g.frame(in: .named("root"))) })
    }
}

// MARK: mascot

struct MascotCanvas: View {
    let pose: Pose
    let dy: Double, sx: Double, sy: Double

    var body: some View {
        let sprite = makeSprite(pose)
        let motion = bodyMotion(pose)
        Canvas { ctx, size in
            var paths = [Path](repeating: Path(), count: palette.count)
            for y in 0..<32 {
                var x = 0
                while x < 32 {
                    let c = sprite.px[y * 32 + x]
                    if c == 0 { x += 1; continue }
                    var e = x
                    while e < 32, sprite.px[y * 32 + e] == c { e += 1 }
                    paths[Int(c)].addRect(CGRect(x: CGFloat(x) * spriteScale, y: CGFloat(y) * spriteScale,
                                                 width: CGFloat(e - x) * spriteScale, height: spriteScale))
                    x = e
                }
            }
            var c = ctx
            c.translateBy(x: size.width / 2 + CGFloat(motion.shake) * spriteScale, y: size.height)
            c.translateBy(x: 0, y: CGFloat(dy + motion.dy * Double(spriteScale)))
            c.scaleBy(x: CGFloat(sx * motion.sx), y: CGFloat(sy * motion.sy))
            c.translateBy(x: -spriteSize / 2, y: -spriteSize)
            for i in 1..<palette.count { c.fill(paths[i], with: .color(palette[i])) }
        }
        .frame(width: spriteSize, height: spriteSize + 110)
        // light rim + soft drop shadow so the outline reads on light and dark windows
        .shadow(color: .white.opacity(0.55), radius: 0.6)
        .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
    }
}

// MARK: root

struct BuddyRoot: View {
    @ObservedObject var model: BuddyModel
    var fixedNow: Date? = nil

    var body: some View {
        if let n = fixedNow { content(n) }
        else {
            TimelineView(.animation(minimumInterval: nil, paused: !model.visible)) { tl in content(tl.date) }
        }
    }

    func content(_ now: Date) -> some View {
        let sinceEnter = max(0, now.timeIntervalSince(model.phaseStart))
        let elapsed = max(0, now.timeIntervalSince(model.shownAt)) + model.ageOffset
        let tier = model.kind == .waiting ? (elapsed < 60 ? 0 : elapsed < 120 ? 1 : 2) : 0
        let exiting = model.exitStart.map { now.timeIntervalSince($0) }
        let k = exiting != nil ? sampleKeys(exitKeys, exiting!) : sampleKeys(enterKeys, sinceEnter)

        // bubble pops after the mascot lands, shrinks away as the mascot leaves
        var bubbleScale = 0.0
        if let e = exiting { bubbleScale = max(0, 1 - e / 0.15) }
        else {
            let b = sinceEnter - 0.5
            if b > 0 { let u = min(1, b / 0.3) - 1; bubbleScale = 1 + 2.70158 * u * u * u + 1.70158 * u * u }
        }
        let chars = Int(max(0, sinceEnter - 0.55) * 48)
        let title: String = {
            if model.kind == .done { return "CLAUDE'S DONE, YOUR TURN" }
            switch tier { case 0: return "CLAUDE'S WAITING ON YOU"; case 1: return "STILL WAITING..."; default: return "HELLOOO? CLAUDE NEEDS YOU" }
        }()
        let pose = Pose(t: elapsed, mood: model.kind, tier: tier, look: model.look)

        return ZStack(alignment: .bottomTrailing) {
            if bubbleScale > 0.01 {
                BubbleView(title: title, message: model.message, project: model.project, chars: chars, tier: tier,
                           onClose: { model.onDismiss() })
                    .scaleEffect(max(0.01, bubbleScale), anchor: UnitPoint(x: BubbleView.tailX / BubbleView.width, y: 1))
                    .padding(.trailing, rightPad)
                    .padding(.bottom, tier == 0 || model.kind == .done ? spriteSize - 34 : spriteSize - 2)
                    .onTapGesture { model.onActivate() }
            }
            MascotCanvas(pose: pose, dy: k.dy, sx: k.sx, sy: k.sy)
                .padding(.trailing, rightPad)
                .contentShape(Rectangle().inset(by: 0))
                .onTapGesture { model.onActivate() }
        }
        .frame(width: winW, height: winH, alignment: .bottomTrailing)
        .coordinateSpace(name: "root")
        .onPreferenceChange(RectKey.self) { model.bubbleRect = $0 }
    }
}

final class ClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
