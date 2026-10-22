import Foundation

/// Hoot, the little owl. A 32x32 pixel sprite drawn in code, one frame per (mood, time).
///
/// This is a line-for-line port of `drawOwl` in `design/mascots/mascots.js`, the file the art was designed and
/// reviewed in. `HootTests` compares this code's output pixel for pixel with frames exported from that JavaScript,
/// so the two cannot drift apart. Change the art there, re-export the fixtures, then port the change here.
public enum HootMood: String, CaseIterable, Sendable {
    case calm       // Claude is working
    case waiting    // needs you
    case annoyed    // still waiting
    case angry      // really waiting
    case done       // finished
}

public enum Hoot {
    public static let size = 32
    /// Every animation repeats seamlessly over this many seconds.
    public static let loopSeconds = 6.0

    /// Palette by index; 0 is transparent.
    public static let palette: [String] = [
        "", "#3d2236",
        "#a0704f", "#6f4733", "#c99872",
        "#ffe9c8", "#e0b98f",
        "#fff6dc", "#ffc83d",
        "#ff9a3c", "#d9741f",
        "#ff8fa3", "#6ec6ff", "#ffd23f", "#ff5a3c", "#b8c6d4", "#ffffff",
    ]

    /// 32*32 palette indexes, row by row.
    public static func frame(_ mood: HootMood, t: Double) -> [UInt8] {
        var c = Grid()
        let ink: UInt8 = 1
        let done = mood == .done, angry = mood == .angry, annoyed = mood == .annoyed, waiting = mood == .waiting
        let calm = mood == .calm

        let bob = done ? 0 : angry ? 0 : (sin(t * snap(2)) > 0.5 ? -1 : 0)
        let ruffle0 = angry ? Int(floor(t * 8)) % 2 : 0
        let oy = bob, puff = Double(ruffle0)
        let lean = waiting ? 1 : angry ? (Int(floor(t * 14)) % 2 != 0 ? 1 : 0) : 0
        let ruffle = angry ? Int(floor(t * 8)) % 2 : 0

        // ear tufts
        func tuft(_ side: Int) {
            let s = Double(side)
            let cx = 16 + s * 7.5
            let peakX = cx + s * (done ? 2.5 : waiting ? 1.5 : 0.5)
            let peakY = Double(3 + oy - (angry ? ruffle : 0) + (annoyed ? 1 : 0) - (waiting ? 1 : 0))
            c.poly([(cx - s * 3.5, Double(10 + oy)), (peakX, peakY), (cx + s * 3, Double(10 + oy))], 2)
            let keep = c.px   // outline the tuft (raw indexing on purpose: it matches the JS, row wrap included)
            func k(_ i: Int) -> UInt8 { i >= 0 && i < keep.count ? keep[i] : 0 }
            for y in 0..<32 { for x in 0..<32 {
                let i = y * 32 + x
                if keep[i] == 0 && (k(i + 1) == 2 || k(i - 1) == 2 || k(i + 32) == 2 || k(i - 32) == 2) { c.set(x, y, ink) }
            } }
        }
        tuft(-1); tuft(1)

        // wings behind: lit from the top left; tips lift away from the body when waiting
        let wy = done ? 13 : 21
        for side in [-1, 1] {
            let s = Double(side)
            let wave = waiting && side == 1 ? (sin(t * snap(6)) > 0 ? -5 : -3) : 0
            let cx = 16 + s * (done ? 8.6 : 10 + puff * 0.4 + (waiting ? 0.2 : 0))
            let cy = Double(wy + oy + wave)
            let shear = waiting ? 0.36 : done ? 0.4 : 0.2
            let ry = done ? 6.4 : 7.2
            for y in 0..<32 { for x in 0..<32 {
                let lean2 = (Double(y) - cy) * shear * s * (done ? -1.3 : 1)
                if Grid.inEllipse(Double(x) - lean2, Double(y), cx, cy, 3.6, ry) { c.set(x, y, side < 0 ? 2 : 3) }
                else if Grid.inEllipse(Double(x) - lean2, Double(y), cx, cy, 4.6, ry + 1) { c.set(x, y, ink) }
            } }
            if side < 0 { for k in 0..<4 { c.set(jsRound(cx - 1), jsRound(cy - 4 + Double(k)), 4) } }
        }

        // body
        let bx = 16 + lean, by = 18 + oy
        let bxd = Double(bx), byd = Double(by)
        c.blob(bxd, byd, 10 + puff, 11.5 + puff * 0.5, 2, ink)
        for y in 0..<32 { for x in 0..<32 where c.get(x, y) == 2 {
            let dx = (Double(x) + 0.5 - bxd) / 10, dy = (Double(y) + 0.5 - byd) / 11.5
            if dx * 0.6 + dy * 0.8 > 0.6 { c.set(x, y, 3) }
        } }
        c.rect(bx - 7, by - 9, 3, 1, 4); c.rect(bx - 8, by - 8, 2, 2, 4)
        // forehead feather marks
        for (i, p) in [(bx - 3, by - 9), (bx, by - 10), (bx + 3, by - 9)].enumerated() {
            let up = angry && (ruffle + i) % 2 != 0 ? 1 : 0
            c.set(p.0, p.1 - up, 3); c.set(p.0, p.1 + 1 - up, 3); c.set(p.0, p.1 + 2 - up, 3)
        }

        // belly
        for y in 0..<32 { for x in 0..<32 where Grid.inEllipse(Double(x), Double(y), bxd, byd + 4.5, 6.3 + puff * 0.6, 7.3) { c.set(x, y, 5) } }
        for y in 0..<32 { for x in 0..<32 where c.get(x, y) == 5
            && Grid.inEllipse(Double(x), Double(y), bxd, byd + 4.5, 7.3 + puff * 0.6, 8.3)
            && !Grid.inEllipse(Double(x), Double(y), bxd, byd + 4.5, 5.4 + puff * 0.6, 6.4) { c.set(x, y, 6) } }
        func mk(_ x: Int, _ y: Int) { c.set(x - 1, y, 6); c.set(x, y + 1, 6); c.set(x + 1, y, 6) }
        mk(bx, by + 2); mk(bx - 3, by + 5); mk(bx + 3, by + 5); mk(bx, by + 8)

        // feet
        let tap = waiting && sin(t * snap(12.5)) > 0 ? -2 : 0
        c.rect(bx - 5, by + 11, 4, 1, 9); c.rect(bx + 1, by + 11 + tap, 4, 1, 9)
        for x in [bx - 5, bx - 3] { c.set(x, by + 12, 10) }
        for x in [bx + 1, bx + 3] { c.set(x, by + 12 + tap, 10) }
        c.rect(bx - 6, by + 11, 1, 1, ink); c.rect(bx + 5, by + 11, 1, 1, ink)

        // eyes: big rings
        let ey = by - 5
        let eyd = Double(ey)
        let exL = bxd - 4.2, exR = bxd + 4.2
        let ringR = 4.1
        func ring(_ cx: Double) {
            for y in 0..<32 { for x in 0..<32 {
                if Grid.inEllipse(Double(x), Double(y), cx, eyd, ringR, ringR) { c.set(x, y, 7) }
                else if Grid.inEllipse(Double(x), Double(y), cx, eyd, ringR + 1, ringR + 1) { c.set(x, y, 3) }
            } }
        }
        ring(exL); ring(exR)
        func blinkAt(_ period: Double, _ len: Double) -> Bool { fmod(t, period) < len }
        let lid = (calm && blinkAt(3, 0.2)) || (waiting && blinkAt(3, 0.14))
        let look: Double = waiting ? (sin(t * snap(1.2)) > 0 ? 1 : 0)
            : calm ? (sin(t * snap(1.9)) > 0.45 ? 1 : sin(t * snap(1.9)) < -0.45 ? -1 : 0) : 0

        func eye(_ cx: Double, _ side: Int) {
            let ix = jsRound(cx), iy = ey
            if done {   // happy arcs
                for k in -2...2 { c.set(ix + k, iy + (abs(k) == 2 ? 1 : abs(k) == 1 ? 0 : -1) + 1, ink) }
                return
            }
            if lid {
                c.rect(ix - 3, iy, 6, 1, ink); c.rect(ix - 3, iy - 3, 6, 3, 2); c.set(ix - 3, iy - 3, 3); c.set(ix + 2, iy - 3, 3)
                return
            }
            let r = annoyed || angry ? 1.9 : calm ? 2.2 : 2.7
            let irisY = eyd + (angry ? 0.5 : 0)
            for y in 0..<32 { for x in 0..<32 where Grid.inEllipse(Double(x), Double(y), cx + look * 0.8, irisY, r, r) { c.set(x, y, 8) } }
            let px = jsRound(cx + look * 0.8) - 1, py = jsRound(irisY) - 1
            c.rect(px, py, 2, 2, ink); c.set(px, py, 16)                    // pupil + glint
            if angry { c.set(px + 1, py + 1, 14) }
            if annoyed {   // flat lid over the top, pupil still showing underneath, brow slanting down at the inner corner
                c.rect(ix - 4, iy - 4, 9, 3, 2)
                for k in -3...3 { c.set(ix + k, iy - 1, ink) }
                c.set(ix - 4, iy - 2, 3); c.set(ix + 4, iy - 2, 3)
                c.line(ix + side * 3, iy - 6, ix - side * 2, iy - 4, ink); c.line(ix + side * 3, iy - 5, ix - side * 2, iy - 3, ink)
                c.rect(px, py + 1, 2, 2, ink); c.set(px, py + 1, 16)
            }
            if angry {   // thick slanted brows, low on the inside
                let ox = ix + side * 4, oyb = ey - 6, ix2 = ix - side * 3, iyb = ey - 3
                c.line(ox, oyb, ix2, iyb, ink); c.line(ox, oyb + 1, ix2, iyb + 1, ink); c.line(ox, oyb + 2, ix2, iyb + 2, 3)
            }
        }
        eye(exL, -1); eye(exR, 1)

        if waiting {   // eyebrows up, listening
            for cx2 in [exL, exR] {
                let ix = jsRound(cx2), iy = ey - 6
                c.set(ix - 2, iy + 1, 3); c.set(ix - 1, iy, 3); c.set(ix, iy, 3); c.set(ix + 1, iy, 3); c.set(ix + 2, iy + 1, 3)
            }
        }

        // beak
        let kx = bx, ky = by - 1
        c.rect(kx - 1, ky, 2, 2, 9); c.set(kx - 1, ky + 2, 10); c.set(kx, ky + 2, 10)
        c.set(kx - 2, ky, ink); c.set(kx + 1, ky, ink); c.set(kx - 2, ky + 1, ink); c.set(kx + 1, ky + 1, ink)
        c.set(kx - 1, ky + 3, ink); c.set(kx, ky + 3, ink)
        if done {
            c.rect(kx - 1, ky + 2, 2, 2, 14)
            c.set(kx - 2, ky + 3, ink); c.set(kx + 1, ky + 3, ink); c.set(kx - 1, ky + 4, ink); c.set(kx, ky + 4, ink)
        }
        // cheeks
        let cc: UInt8 = done || calm || waiting ? 11 : angry ? 14 : 0
        if cc != 0 { c.rect(bx - 9, by, 2, 1, cc); c.rect(bx + 7, by, 2, 1, cc) }

        // extras
        if annoyed {
            c.sweat(bx + 10, by - 14 + (sin(t * snap(2)) > 0 ? 1 : 0), 12, 16)
            c.glyph("?", 1, 1, 13)
        }
        if angry {
            c.glyph("!", 1, 4 + Int(floor(t * 8)) % 2, 14)
            c.glyph("!", 4, 4 + Int(floor(t * 8 + 1)) % 2, 14)
            let s = Int(floor(t * 6)) % 2
            c.puff(bx + 10, 5 - s, 15)
        }
        if done {
            let k = Int(floor(t * 6))
            for (i, p) in [(3, 8), (28, 9), (3, 18), (28, 18), (24, 5), (6, 4), (27, 26), (4, 26)].enumerated() where (k + i) % 3 != 0 {
                c.plus(p.0, p.1 + (k + i) % 2, 13)
            }
        }
        return c.px
    }

    /// JavaScript's Math.round: halves round up (toward +infinity), unlike Swift's `.rounded()`.
    static func jsRound(_ x: Double) -> Int { Int(floor(x + 0.5)) }

    /// Snaps a frequency (radians per second) so its period divides `loopSeconds`, making the loop seamless.
    static func snap(_ k: Double) -> Double {
        let base = 2 * Double.pi / loopSeconds
        return max(1, Double(jsRound(k / base))) * base
    }

    struct Grid {
        var px = [UInt8](repeating: 0, count: 32 * 32)
        func get(_ x: Int, _ y: Int) -> UInt8 { x < 0 || x >= 32 || y < 0 || y >= 32 ? 0 : px[y * 32 + x] }
        mutating func set(_ x: Int, _ y: Int, _ c: UInt8) { if x >= 0 && x < 32 && y >= 0 && y < 32 { px[y * 32 + x] = c } }
        mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt8) {
            guard w > 0, h > 0 else { return }
            for j in 0..<h { for i in 0..<w { set(x + i, y + j, c) } }
        }
        static func inEllipse(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Bool {
            let dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry
            return dx * dx + dy * dy <= 1
        }
        /// A filled ellipse with a 1px outline drawn over whatever is behind it.
        mutating func blob(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ fill: UInt8, _ ink: UInt8) {
            for y in 0..<32 { for x in 0..<32 {
                if Grid.inEllipse(Double(x), Double(y), cx, cy, rx, ry) { set(x, y, fill) }
                else if Grid.inEllipse(Double(x), Double(y), cx, cy, rx + 1, ry + 1) { set(x, y, ink) }
            } }
        }
        mutating func line(_ x0In: Int, _ y0In: Int, _ x1: Int, _ y1: Int, _ c: UInt8) {
            var x0 = x0In, y0 = y0In
            let dx = abs(x1 - x0), dy = -abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
            var err = dx + dy
            while true {
                set(x0, y0, c)
                if x0 == x1 && y0 == y1 { break }
                let e2 = 2 * err
                if e2 >= dy { err += dy; x0 += sx }
                if e2 <= dx { err += dx; y0 += sy }
            }
        }
        /// Scanline fill of a small convex polygon.
        mutating func poly(_ pts: [(Double, Double)], _ c: UInt8) {
            let y0 = Int(pts.map { $0.1 }.min()!), y1 = Int(pts.map { $0.1 }.max()!)
            guard y0 <= y1 else { return }
            for y in y0...y1 {
                var xs: [Double] = []
                for i in 0..<pts.count {
                    let (ax, ay) = pts[i], (bx, by) = pts[(i + 1) % pts.count]
                    let yy = Double(y) + 0.5
                    if (ay <= yy && by > yy) || (by <= yy && ay > yy) { xs.append(ax + (yy - ay) / (by - ay) * (bx - ax)) }
                }
                xs.sort()
                var i = 0
                while i + 1 < xs.count {
                    for x in Hoot.jsRound(xs[i])..<max(Hoot.jsRound(xs[i]), Hoot.jsRound(xs[i + 1])) { set(x, y, c) }
                    i += 2
                }
            }
        }
        /// 3 wide x 5 tall "!" or "?".
        mutating func glyph(_ ch: Character, _ x: Int, _ y: Int, _ c: UInt8) {
            let rows = ch == "!" ? ["010", "010", "010", "000", "010"] : ["110", "001", "010", "000", "010"]
            for (j, r) in rows.enumerated() { for (i, b) in r.enumerated() where b == "1" { set(x + i, y + j, c) } }
        }
        mutating func plus(_ x: Int, _ y: Int, _ c: UInt8) { set(x, y, c); set(x - 1, y, c); set(x + 1, y, c); set(x, y - 1, c); set(x, y + 1, c) }
        mutating func sweat(_ x: Int, _ y: Int, _ c: UInt8, _ hi: UInt8) {
            set(x, y, c); set(x, y + 1, c); set(x - 1, y + 2, c); set(x, y + 2, c); set(x + 1, y + 2, c); set(x, y + 3, c); set(x, y + 1, hi)
        }
        /// A small cloud with a plum outline.
        mutating func puff(_ x: Int, _ y: Int, _ c: UInt8) {
            let cells = [(x, y), (x + 1, y), (x + 2, y), (x, y + 1), (x + 1, y + 1), (x + 2, y + 1), (x + 1, y - 1), (x + 2, y - 1)]
            let inside = Set(cells.map { "\($0.0),\($0.1)" })
            for (cx, cy) in cells { for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !inside.contains("\(cx + dx),\(cy + dy)") { set(cx + dx, cy + dy, 1) } }
            for (cx, cy) in cells { set(cx, cy, c) }
        }
    }
}
