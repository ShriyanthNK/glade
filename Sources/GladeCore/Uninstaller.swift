import Foundation

/// Removes everything Glade put on this Mac: its Claude Code hooks and status line (restoring one it replaced),
/// the command-line links, and its support directory. Unrelated settings and links are left alone.
public struct Uninstaller {
    public let supportDir: String
    public let settingsPath: String
    public let links: [String]

    public init(supportDir: String = GladeCore.supportDir, settingsPath: String = claudeSettingsPath,
                links: [String] = [NSHomeDirectory() + "/.local/bin/glade", NSHomeDirectory() + "/.local/bin/claude-buddy"]) {
        self.supportDir = supportDir
        self.settingsPath = settingsPath
        self.links = links
    }

    /// Returns a human-readable list of what was done. Throws before changing anything if settings.json is unreadable.
    @discardableResult
    public func run() throws -> [String] {
        var done: [String] = []
        let hooks = HookInstaller(settingsPath: settingsPath, hookPath: supportDir + "/hook.sh")
        let line = StatusLineInstaller(settingsPath: settingsPath, scriptPath: supportDir + "/statusline.sh",
                                       previousPath: supportDir + "/statusline.previous.json")
        if FileManager.default.fileExists(atPath: settingsPath) {
            if try hooks.uninstall() != nil { done.append("Removed Glade's Claude Code hooks") }
            if try line.uninstall() != nil { done.append("Removed Mochi's status line") }
        }
        let fm = FileManager.default
        for link in links {
            // only links that point into a Glade / claude-buddy install, never someone else's `glade`
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: link),
                  dest.contains("/.glade/") || dest.contains("Glade.app") || dest.contains("/.claude-buddy/") else { continue }
            try? fm.removeItem(atPath: link)
            done.append("Removed \(link)")
        }
        if fm.fileExists(atPath: supportDir) {
            try fm.removeItem(atPath: supportDir)
            done.append("Deleted \(supportDir)")
        }
        return done
    }
}
