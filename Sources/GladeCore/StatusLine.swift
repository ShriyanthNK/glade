import Foundation

/// Hoot in Claude Code's status line: its mood follows how full the context window is.
/// Calm under 60%, impatient from 60%, worried from 85%. Uses plutil (always present on macOS) to read
/// the JSON Claude Code sends, so there is no jq dependency.
public let statusLineScript = #"""
#!/bin/sh
# Glade status line: Hoot's mood follows how full Claude's context window is.
input=$(cat)
get() { printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }
model=$(get model.display_name); [ -n "$model" ] || model="Claude"
dir=$(get workspace.current_dir); dir=${dir##*/}
pct=$(get context_window.used_percentage); pct=${pct%%.*}
case "$pct" in ''|*[!0-9]*) pct=0 ;; esac
if [ "$pct" -ge 85 ]; then face='{>,<}'; word='HELLOOO?'; c=196
elif [ "$pct" -ge 60 ]; then face='{-,-}'; word='still here...'; c=215
else face='{o,o}'; word='all good'; c=114; fi
filled=$((pct / 10)); [ "$filled" -gt 10 ] && filled=10
bar=''; i=1
while [ "$i" -le 10 ]; do
  if [ "$i" -le "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
  i=$((i + 1))
done
printf '\033[38;5;180m🦉\033[38;5;223m%s \033[1;38;5;%sm%s\033[0m  \033[38;5;180m%s\033[0m' "$face" "$c" "$word" "$model"
[ -n "$dir" ] && printf ' · \033[38;5;223m%s\033[0m' "$dir"
printf '  \033[38;5;%sm%s\033[0m %s%%\n' "$c" "$bar" "$pct"

"""#

public enum StatusLineError: Error, Equatable, CustomStringConvertible {
    case otherInUse(String)
    public var description: String {
        switch self {
        case .otherInUse(let cmd): return "Claude Code already uses a status line (\(cmd)). Replace it to use Hoot's; Glade can restore it later."
        }
    }
}

/// Adds and removes Glade's `statusLine` entry in settings.json. Never overwrites someone else's status line
/// unless asked to, and puts the old one back when Glade's is removed.
public struct StatusLineInstaller {
    public enum Status: Equatable {
        case installed
        case notInstalled
        case otherInUse(command: String)
        case unreadable
    }

    public let settingsPath: String
    public let scriptPath: String
    public let previousPath: String
    private var file: SettingsFile { SettingsFile(path: settingsPath) }

    public init(settingsPath: String = claudeSettingsPath, scriptPath: String = supportDir + "/statusline.sh",
                previousPath: String = supportDir + "/statusline.previous.json") {
        self.settingsPath = settingsPath
        self.scriptPath = scriptPath
        self.previousPath = previousPath
    }

    private func command(of root: [String: Any]) -> String? {
        (root["statusLine"] as? [String: Any])?["command"] as? String
    }

    private func isOurs(_ cmd: String) -> Bool { cmd.contains("/.glade/statusline.sh") || cmd == scriptPath }

    public func status() -> Status {
        guard let root = try? file.load() else { return .unreadable }
        guard let cmd = command(of: root), !cmd.isEmpty else { return .notInstalled }
        return isOurs(cmd) ? .installed : .otherInUse(command: cmd)
    }

    @discardableResult
    public func install(replacingOther: Bool = false) throws -> String? {
        var root = try file.load()
        if let cmd = command(of: root), !cmd.isEmpty, !isOurs(cmd) {
            guard replacingOther else { throw StatusLineError.otherInUse(cmd) }
            if let old = root["statusLine"], let data = try? JSONSerialization.data(withJSONObject: old, options: [.sortedKeys]) {
                try FileManager.default.createDirectory(atPath: (previousPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try data.write(to: URL(fileURLWithPath: previousPath))
            }
        }
        try FileManager.default.createDirectory(atPath: (scriptPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try statusLineScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        root["statusLine"] = ["type": "command", "command": scriptPath]
        return try file.write(root)
    }

    /// Removes Glade's status line (and restores the one it replaced, if any). Leaves anyone else's alone.
    @discardableResult
    public func uninstall() throws -> String? {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return nil }
        var root = try file.load()
        guard let cmd = command(of: root), isOurs(cmd) else { return nil }
        if let data = FileManager.default.contents(atPath: previousPath),
           let old = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root["statusLine"] = old
            try? FileManager.default.removeItem(atPath: previousPath)
        } else {
            root["statusLine"] = nil
        }
        return try file.write(root)
    }
}
