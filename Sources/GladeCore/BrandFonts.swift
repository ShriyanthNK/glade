import AppKit
import CoreText
import Foundation

/// Glade's three typefaces, all SIL Open Font License, bundled in `Resources/Fonts` with their license texts:
/// Bricolage Grotesque (display and titles), Pixelify Sans (small pixel-style labels and buttons) and
/// JetBrains Mono (Hoot's voice: bubbles and numbers). Registered for this process only.
public enum BrandFonts {
    public static let display = "BricolageGrotesque-ExtraBold"
    public static let ui = "BricolageGrotesque-SemiBold"
    public static let label = "PixelifySans-Bold"
    public static let labelRegular = "PixelifySans-SemiBold"
    public static let voice = "JetBrainsMono-ExtraBold"
    public static let mono = "JetBrainsMono-Medium"
    public static let all = [display, ui, label, labelRegular, voice, mono]

    /// GLADE_FONTS, else the app bundle's Resources/Fonts, else the repo's Resources/Fonts (swift run / tests).
    public static func directory() -> String {
        if let e = ProcessInfo.processInfo.environment["GLADE_FONTS"] { return e }
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Fonts").path, FileManager.default.fileExists(atPath: r) { return r }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Fonts").path
    }

    /// Registers every .ttf in the fonts directory for this process. Safe to call more than once.
    @discardableResult
    public static func register(from dir: String = directory()) -> Int {
        let urls = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".ttf") }.map { URL(fileURLWithPath: dir + "/" + $0) as CFURL }
        guard !urls.isEmpty else { return 0 }
        CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)   // already-registered fonts just report an error we ignore
        return urls.count
    }
}
