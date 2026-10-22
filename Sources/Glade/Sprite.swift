import SwiftUI
import GladeCore

enum Mood { case waiting, done }

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

/// Hoot's palette, by sprite index (0 is transparent). The pixels come from GladeCore's `Hoot`.
let palette: [Color] = Hoot.palette.map { hex in
    hex.isEmpty ? Color.clear : Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0)
}

struct Sprite {
    var px: [UInt8]

    func get(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0, x < 32, y >= 0, y < 32 else { return 0 }
        return px[y * 32 + x]
    }
}

struct Pose {
    var t: Double          // seconds since shown (plus any test age)
    var mood: Mood
    var tier: Int          // impatience: 0 waiting, 1 annoyed after 1 min, 2 angry after 2 min
    var look: Int          // unused by Hoot, kept so callers do not change
}

/// Which of Hoot's five moods a pop-up pose shows.
func hootMood(for p: Pose) -> HootMood {
    switch p.mood {
    case .done: return .done
    case .waiting: return p.tier == 0 ? .waiting : p.tier == 1 ? .annoyed : .angry
    }
}

func makeSprite(_ p: Pose) -> Sprite { Sprite(px: Hoot.frame(hootMood(for: p), t: max(0, p.t))) }
func makeSprite(hoot: HootMood, t: Double) -> Sprite { Sprite(px: Hoot.frame(hoot, t: max(0, t))) }

/// Hoot animates inside the sprite itself (bobbing, tapping, ruffling), so the pop-up adds no extra hop or shake.
func bodyMotion(_ p: Pose) -> (dy: Double, sx: Double, sy: Double, shake: Int) { (0, 1, 1, 0) }
