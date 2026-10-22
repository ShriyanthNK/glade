import AppKit
import CoreText
import Foundation

/// A monospaced font family the user can pick for Glade terminals.
public struct FontChoice: Identifiable, Equatable {
    public var id: String { family }
    public let family: String
    /// PostScript name of the regular face; what Terminal's profile stores.
    public let postScript: String
    /// True when this Mac only has it because Glade ships it (so Terminal cannot use it until it is installed).
    public let needsInstall: Bool
}

public enum TerminalFonts {
    public static let defaultSize = 14.0
    public static let sizeRange = 10.0...24.0
    static let preferred = ["JetBrains Mono", "SF Mono", "Menlo", "Monaco", "Fira Code", "Source Code Pro", "IBM Plex Mono",
                            "Hack", "Cascadia Code", "Courier New"]

    /// Installed monospaced families, favourites first. Fonts that exist only inside Glade are marked `needsInstall`.
    public static func installed(bundledDir: String = BrandFonts.directory()) -> [FontChoice] {
        let fm = NSFontManager.shared
        var out: [FontChoice] = []
        for family in fm.availableFontFamilies {
            guard let members = fm.availableMembers(ofFontFamily: family), !members.isEmpty else { continue }
            // prefer the plain face
            let pick = members.first { ($0[1] as? String) == "Regular" } ?? members.first { ($0[1] as? String) == "Medium" } ?? members[0]
            guard let ps = pick[0] as? String, let font = NSFont(name: ps, size: 12), font.isFixedPitch else { continue }
            var processOnly = false
            if let url = CTFontCopyAttribute(CTFontCreateWithName(ps as CFString, 12, nil), kCTFontURLAttribute) as? URL {
                processOnly = url.path.hasPrefix(bundledDir)
            }
            out.append(FontChoice(family: family, postScript: ps, needsInstall: processOnly))
        }
        func rank(_ f: FontChoice) -> Int { preferred.firstIndex(of: f.family) ?? preferred.count }
        return out.sorted { (rank($0), $0.family.lowercased()) < (rank($1), $1.family.lowercased()) }
    }

    /// The PostScript name Terminal should use. Unknown or not-yet-installed choices fall back to Menlo.
    public static func resolveName(family: String, choices: [FontChoice]) -> String {
        if family.isEmpty {
            if let jb = choices.first(where: { $0.family == "JetBrains Mono" && !$0.needsInstall }) { return jb.postScript }
            return "Menlo-Regular"
        }
        if let c = choices.first(where: { $0.family == family && !$0.needsInstall }) { return c.postScript }
        return "Menlo-Regular"
    }
}

/// Copies Glade's bundled JetBrains Mono into ~/Library/Fonts so Terminal can use it, and remembers exactly which
/// files it added so uninstalling removes those and nothing else.
public struct FontInstaller {
    public static let files = ["JetBrainsMono-Medium.ttf", "JetBrainsMono-ExtraBold.ttf"]
    public let source: String
    public let destination: String
    public let marker: String

    public init(source: String = BrandFonts.directory(), destination: String = NSHomeDirectory() + "/Library/Fonts",
                marker: String = supportDir + "/installed-fonts.txt") {
        self.source = source; self.destination = destination; self.marker = marker
    }

    public var isInstalled: Bool { Self.files.allSatisfy { FileManager.default.fileExists(atPath: destination + "/" + $0) } }

    @discardableResult
    public func install() throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
        var added = recorded()
        var copied: [String] = []
        for f in Self.files where !fm.fileExists(atPath: destination + "/" + f) {   // never overwrite a font the user already has
            try fm.copyItem(atPath: source + "/" + f, toPath: destination + "/" + f)
            copied.append(f); added.append(f)
        }
        if !copied.isEmpty {
            try fm.createDirectory(atPath: (marker as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try added.joined(separator: "\n").write(toFile: marker, atomically: true, encoding: .utf8)
        }
        return copied
    }


    func recorded() -> [String] {
        ((try? String(contentsOfFile: marker, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init).filter { Self.files.contains($0) }
    }

    @discardableResult
    public func uninstall() throws -> [String] {
        var removed: [String] = []
        for f in recorded() where FileManager.default.fileExists(atPath: destination + "/" + f) {
            try FileManager.default.removeItem(atPath: destination + "/" + f)
            removed.append(f)
        }
        try? FileManager.default.removeItem(atPath: marker)
        return removed
    }
}
