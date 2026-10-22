import AppKit
import Foundation

/// Glade's Terminal.app profile: Mochi's palette, and a translucent plum background so the scene shows through.
public enum TerminalProfile {
    public static let name = "Glade"
    public static let columns = 110
    public static let rows = 32

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    static func archive(_ object: NSObject) -> Data {
        (try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)) ?? Data()
    }

    /// The profile as a `.terminal` property list. `tint` is the background opacity; it must match
    /// `LookPipeline.Options.terminalTint`, which the backdrops' contrast is solved against.
    public static func plist(tint: Double = LookPipeline.Options().terminalTint) -> [String: Any] {
        let font = NSFont(name: "JetBrainsMono-Regular", size: 14) ?? NSFont(name: "Menlo-Regular", size: 14)
            ?? NSFont.userFixedPitchFont(ofSize: 14)!
        var p: [String: Any] = [
            "name": name, "type": "Window Settings", "ProfileCurrentVersion": 2.07,
            "BackgroundColor": archive(color(0x2A1A26, alpha: CGFloat(tint))),
            "BackgroundBlur": 0.0,
            "TextColor": archive(color(0xFFF4DC)), "BoldTextColor": archive(color(0xFFFFFF)),
            "CursorColor": archive(color(0xFFD23F)), "SelectionColor": archive(color(0x5A3A52)),
            "UseBrightBold": false, "CursorType": 0, "columnCount": columns, "rowCount": rows,
            "Font": archive(font),
        ]
        // ANSI palette: black, red, green, yellow, blue, magenta, cyan, white, then the bright row
        let ansi: [(String, UInt32, UInt32)] = [
            ("Black", 0x3B2230, 0x7A5A70), ("Red", 0xFF6B7F, 0xFF8FA8), ("Green", 0x5DC46A, 0x8FE39A),
            ("Yellow", 0xFFD23F, 0xFFE27A), ("Blue", 0x6EC6FF, 0xA6DCFF), ("Magenta", 0xFF8FA8, 0xFFB3C6),
            ("Cyan", 0x2BA89A, 0x5FD6C8), ("White", 0xFFD9B8, 0xFFF4DC),
        ]
        for (n, normal, bright) in ansi {
            p["ANSI\(n)Color"] = archive(color(normal))
            p["ANSIBright\(n)Color"] = archive(color(bright))
        }
        return p
    }

    public static func write(to path: String, tint: Double = LookPipeline.Options().terminalTint) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist(tint: tint), format: .xml, options: 0)
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

/// Small pure helpers for the scenery window tracker.
public enum SceneryMath {
    /// AppleScript prints a list of window ids as "123, 456" (or nothing).
    public static func parseWindowIDs(_ output: String) -> [Int] {
        output.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }).compactMap { Int($0) }
    }

    /// Core Graphics window bounds (origin top-left of the primary display) to Cocoa (origin bottom-left).
    public static func cocoaRect(cg: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: cg.minX, y: primaryScreenHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    /// Integer scale that makes a 480x270 backdrop cover a window of this size (crisp pixels, no blur).
    public static func backdropScale(windowWidth: CGFloat, windowHeight: CGFloat) -> CGFloat {
        max(1, max(windowWidth / CGFloat(LookPipeline.width), windowHeight / CGFloat(LookPipeline.height)).rounded(.up))
    }
}
