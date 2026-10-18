import SwiftUI

enum Mood { case waiting, done }

// Palette indices
enum P {
    static let ink: UInt8 = 1, body: UInt8 = 2, shade: UInt8 = 3, hi: UInt8 = 4, cheek: UInt8 = 5
    static let leaf: UInt8 = 6, leafD: UInt8 = 7, white: UInt8 = 8, paper: UInt8 = 9, wood: UInt8 = 10
    static let sweat: UInt8 = 11, red: UInt8 = 12, gold: UInt8 = 13, pink: UInt8 = 14, teal: UInt8 = 15, mouth: UInt8 = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

let palette: [Color] = [
    .clear, Color(hex: 0x3d2236), Color(hex: 0xffd9b8), Color(hex: 0xf0a487), Color(hex: 0xfff3e4),
    Color(hex: 0xff8fa3), Color(hex: 0x62c46d), Color(hex: 0x2f8f4e), Color(hex: 0xffffff),
    Color(hex: 0xfff6dc), Color(hex: 0xb8794a), Color(hex: 0x6ec6ff), Color(hex: 0xff4d5e),
    Color(hex: 0xffd23f), Color(hex: 0xff7eb6), Color(hex: 0x3fd0c0), Color(hex: 0xb03a52),
]

struct Sprite {
    static let n = 32
    var px = [UInt8](repeating: 0, count: 32 * 32)

    func get(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0, x < 32, y >= 0, y < 32 else { return 0 }
        return px[y * 32 + x]
    }
    mutating func set(_ x: Int, _ y: Int, _ c: UInt8) {
        guard x >= 0, x < 32, y >= 0, y < 32 else { return }
        px[y * 32 + x] = c
    }
    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt8) {
        guard w > 0, h > 0 else { return }
        for j in 0..<h { for i in 0..<w { set(x + i, y + j, c) } }
    }
    mutating func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, c: UInt8, maxY: Int) {
        for y in 0...maxY {
            for x in 0..<32 {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1 { set(x, y, c) }
            }
        }
    }
    /// Light from the top-left: highlight blob, shadow on the lower right.
    mutating func shade(cx: Double, cy: Double, rx: Double, ry: Double) {
        for y in 0..<32 {
            for x in 0..<32 where get(x, y) == P.body {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                let d2 = dx * dx + dy * dy
                if dx * 0.6 + dy * 0.8 > 0.6 { set(x, y, P.shade) }
            }
        }
    }
    mutating func outline(_ c: UInt8) {
        var add: [(Int, Int)] = []
        for y in 0..<32 {
            for x in 0..<32 where get(x, y) == 0 {
                if get(x + 1, y) != 0 || get(x - 1, y) != 0 || get(x, y + 1) != 0 || get(x, y - 1) != 0 { add.append((x, y)) }
            }
        }
        for (x, y) in add { set(x, y, c) }
    }
    mutating func glyph(_ ch: Character, _ x: Int, _ y: Int, _ c: UInt8) {
        let rows: [String]
        switch ch {
        case "!": rows = ["010", "010", "010", "000", "010"]
        case "?": rows = ["110", "001", "010", "000", "010"]
        default: rows = []
        }
        for (j, r) in rows.enumerated() { for (i, b) in r.enumerated() where b == "1" { set(x + i, y + j, c) } }
    }
    mutating func plus(_ x: Int, _ y: Int, _ c: UInt8) {
        set(x, y, c); set(x - 1, y, c); set(x + 1, y, c); set(x, y - 1, c); set(x, y + 1, c)
    }
}

struct Pose {
    var t: Double          // seconds since shown (plus any test age)
    var mood: Mood
    var tier: Int          // impatience: 0 calm, 1 after 1 min, 2 after 5 min
    var look: Int          // -1 / 0 / 1 toward the mouse, 0 = idle schedule
}

/// Body-level motion in sprite pixels / scale factors (hops, squash, shake).
func bodyMotion(_ p: Pose) -> (dy: Double, sx: Double, sy: Double, shake: Int) {
    let t = p.t
    switch p.mood {
    case .done:
        let ph = fmod(t, 1.3) / 1.3
        if ph < 0.5 {
            let u = sin(.pi * ph / 0.5)
            return (-u * 5, 1 - 0.05 * u, 1 + 0.07 * u, 0)
        } else if ph < 0.62 {
            let u = sin(.pi * (ph - 0.5) / 0.12)
            return (0, 1 + 0.08 * u, 1 - 0.1 * u, 0)
        }
        return (0, 1, 1, 0)
    case .waiting:
        if p.tier == 2 {
            let hop = fmod(t, 1.6)
            let dy = hop < 0.3 ? -sin(.pi * hop / 0.3) * 2 : 0
            return (dy, 1, 1, Int(t * 16) % 2 == 0 ? 0 : 1)
        }
        return (0, 1, 1, 0)
    }
}

func makeSprite(_ p: Pose) -> Sprite {
    var s = Sprite()
    let t = p.t
    let waiting = p.mood == .waiting
    let tier = waiting ? p.tier : 0

    let rate = waiting ? (tier == 2 ? 3.6 : 2.0) : 3.2
    let br = sin(t * rate) > 0 ? 1 : 0
    let ry = 9.0 + (br == 1 ? 0.9 : 0)
    let cy = 30.0 - ry
    s.ellipse(cx: 16, cy: cy, rx: 11, ry: ry, c: P.body, maxY: 29)
    s.shade(cx: 16, cy: cy, rx: 11, ry: ry)
    let topY = Int((cy - ry).rounded())

    // sprout
    let sway = sin(t * 1.6) > 0.55 ? 1 : 0
    let perk = p.mood == .done ? (Int(t * 6) % 2) : 0
    s.rect(16, topY - 4, 2, 4, P.leafD)
    s.rect(13 + sway - perk, topY - 4 - perk, 3, 2, P.leaf)
    s.rect(18 + sway + perk, topY - 5 - perk, 3, 2, P.leaf)

    // feet (right foot taps)
    var tapDown = false
    var tapping = false
    if waiting {
        switch tier {
        case 0: tapping = fmod(t, 4) < 1.3; if tapping { tapDown = Int(t * 4) % 2 == 0 }
        case 1: tapping = true; tapDown = Int(t * 6) % 2 == 0
        default: tapping = true; tapDown = Int(t * 8) % 2 == 0
        }
    }
    s.rect(10, 30, 4, 2, P.shade)
    s.rect(18, tapping && !tapDown ? 29 : 30, 4, 2, P.shade)

    // arms and sign
    func armDown(_ x: Int) { s.rect(x, 21, 2, 4, P.shade) }
    let signText: String? = waiting ? (tier == 1 ? "?" : tier == 2 ? "!!" : nil) : nil
    if p.mood == .done {
        let b = Int(t * 6) % 2
        s.rect(3, 13 + b, 2, 7, P.shade)
        s.rect(27, 14 - b, 2, 7, P.shade)
    } else if let text = signText {
        armDown(3)
        s.rect(27, 16, 2, 5, P.shade)
        s.rect(26, 9, 2, 8, P.wood)
        s.rect(21, 0, 10, 9, P.wood)
        s.rect(22, 1, 8, 7, P.paper)
        _ = text
    } else {
        armDown(3)
        let waveCycle = fmod(t + 2, 7.5)
        if waveCycle < 1.8 {
            let f = Int(t * 8) % 2
            s.rect(27 + f, 12, 2, 8, P.shade)
        } else {
            armDown(27)
        }
    }
    s.outline(P.ink)
    // glossy highlight
    for (hx, hy) in [(9, 4), (9, 3), (10, 2), (11, 1), (12, 1), (9, 6)] { s.set(hx, topY + hy, P.hi) }

    // sign glyphs (after outline so they stay crisp)
    if let text = signText {
        let col = tier == 2 ? P.red : P.ink
        if text.count == 1 { s.glyph(text.first!, 25, 2, col) }
        else { s.glyph("!", 23, 2, col); s.glyph("!", 27, 2, col) }
    }

    // face
    let by = 19 - br
    let blinking = fmod(t + 0.7, 3.7) > 3.55
    var look = p.look
    if look == 0 {
        let c = fmod(t, 9)
        if c > 4 && c < 5 { look = -1 } else if c > 5.6 && c < 6.6 { look = 1 }
    }
    if p.mood == .done {
        for (x, dx) in [(10, 0), (19, 0)] {
            _ = dx
            s.set(x, by, P.ink); s.set(x + 1, by - 1, P.ink); s.set(x + 2, by - 1, P.ink); s.set(x + 3, by, P.ink)
        }
    } else if blinking {
        s.rect(11 + look, by + 1, 2, 1, P.ink); s.rect(20 + look, by + 1, 2, 1, P.ink)
    } else if tier == 1 {
        // unimpressed half-lids
        s.rect(10 + look, by - 1, 4, 1, P.ink); s.rect(19 + look, by - 1, 4, 1, P.ink)
        s.rect(11 + look, by, 2, 2, P.ink); s.rect(20 + look, by, 2, 2, P.ink)
    } else {
        s.rect(11 + look, by - 1, 2, 3, P.ink); s.rect(20 + look, by - 1, 2, 3, P.ink)
        s.set(11 + look, by - 1, P.white); s.set(20 + look, by - 1, P.white)
        if tier == 2 {
            s.rect(10, by - 3, 2, 1, P.ink); s.rect(12, by - 2, 2, 1, P.ink)
            s.rect(21, by - 3, 2, 1, P.ink); s.rect(19, by - 2, 2, 1, P.ink)
        }
    }
    let cheekC = tier == 2 ? P.red : P.cheek
    s.rect(8, by + 3, 3, 2, cheekC); s.rect(22, by + 3, 3, 2, cheekC)
    if p.mood == .done {
        s.rect(14, by + 3, 5, 2, P.mouth)
        s.rect(14, by + 3, 5, 1, P.ink)
        s.rect(16, by + 4, 2, 1, P.pink)
    } else if tier == 0 {
        s.set(15, by + 3, P.ink); s.set(16, by + 4, P.ink); s.set(17, by + 3, P.ink)
    } else if tier == 1 {
        s.rect(15, by + 4, 3, 1, P.ink)
    } else {
        s.set(14, by + 4, P.ink); s.set(15, by + 3, P.ink); s.set(16, by + 4, P.ink); s.set(17, by + 3, P.ink); s.set(18, by + 4, P.ink)
    }

    // tap impact marks
    if tapping && tapDown { s.set(23, 30, P.ink); s.set(24, 29, P.ink); s.set(24, 31, P.ink) }

    // extras
    if tier >= 1 {
        let drop = Int(fmod(t * 2, 4))
        s.rect(6, topY + 3 + drop, 1, 2, P.sweat)
    }
    if tier == 2 {
        for i in 0..<2 {
            let rise = Int(fmod(t * 3 + Double(i) * 3, 6))
            s.rect(i == 0 ? 6 : 2, topY - rise + (i == 0 ? 1 : 4), 2, 2, P.white)
        }
    }
    if p.mood == .done {
        let spots = [(4, 7), (28, 9), (8, 3), (24, 4)]
        for (i, sp) in spots.enumerated() where sin(t * 5 + Double(i) * 1.7) > 0.1 { s.plus(sp.0, sp.1, P.gold) }
        if t < 3.5 {
            let cols = [P.pink, P.teal, P.gold, P.sweat]
            for i in 0..<12 {
                let x = (i * 11 + 3) % 30
                let y = Int(fmod(t * 9 + Double(i) * 7, 30))
                if s.get(x, y) == 0 && s.get(x + 1, y) == 0 { s.rect(x, y, 2, 1, cols[i % 4]) }
            }
        }
    }
    return s
}
