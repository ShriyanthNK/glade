import Foundation

/// The script Claude Code runs for each hook event. It forwards the event to the running app over the
/// socket and returns immediately; the app is started on demand for events that need it.
public let hookScript = """
#!/bin/sh
# Glade hook: forwards a Claude Code hook event to the Glade app.
# Returns immediately; all real work happens in a detached background job.
ev="$1"
home="${GLADE_HOME:-$HOME/.glade}"
sock="$home/glade.sock"
payload=$(cat | tr -d '\\n')
{
  msg=$(printf '%s\\n%s\\n\\n%s\\n' "$ev" "${__CFBundleIdentifier:-}" "$payload")
  if ! printf '%s' "$msg" | /usr/bin/nc -U -w 1 "$sock" >/dev/null 2>&1; then
    case "$ev" in
      Notification|Stop)
        /usr/bin/open -g "$home/Glade.app"
        i=0
        while [ "$i" -lt 25 ]; do
          sleep 0.2
          printf '%s' "$msg" | /usr/bin/nc -U -w 1 "$sock" >/dev/null 2>&1 && break
          i=$((i + 1))
        done ;;
    esac
  fi
} </dev/null >/dev/null 2>&1 &
exit 0

"""

public let claudeSettingsPath = ProcessInfo.processInfo.environment["GLADE_CLAUDE_SETTINGS"]
    ?? NSHomeDirectory() + "/.claude/settings.json"

/// Adds and removes Glade's entries in Claude Code's settings.json, leaving everything else alone.
/// A timestamped backup is written next to the file before every change.
public struct HookInstaller {
    public static let events = ["Notification", "Stop", "UserPromptSubmit", "PostToolUse"]
    /// Substrings that mark a hook command as ours: this install, and the earlier claude-buddy one.
    static let marks = ["/.glade/hook.sh", "/.claude-buddy/hook.sh"]

    public enum Status: Equatable {
        case installed
        case partial(missing: [String])
        case notInstalled
        case unreadable
    }

    public let settingsPath: String
    public let hookPath: String
    private var file: SettingsFile { SettingsFile(path: settingsPath) }

    public init(settingsPath: String = claudeSettingsPath, hookPath: String = supportDir + "/hook.sh") {
        self.settingsPath = settingsPath
        self.hookPath = hookPath
    }

    private func isOurs(_ command: String) -> Bool {
        command.contains(hookPath) || Self.marks.contains { command.contains($0) }
    }

    private func commands(in entry: Any) -> [String] {
        guard let e = entry as? [String: Any], let hooks = e["hooks"] as? [[String: Any]] else { return [] }
        return hooks.compactMap { $0["command"] as? String }
    }

    public func status() -> Status {
        guard let root = try? file.load() else { return .unreadable }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let missing = Self.events.filter { ev in
            !((hooks[ev] as? [Any]) ?? []).contains { commands(in: $0).contains { $0.hasSuffix(" " + ev) && isOurs($0) } }
        }
        if missing.isEmpty { return .installed }
        return missing.count == Self.events.count ? .notInstalled : .partial(missing: missing)
    }

    /// Writes the hook script, then merges four hook entries into settings.json. Returns the backup path, if any.
    @discardableResult
    public func install() throws -> String? {
        var root = try file.load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for ev in Self.events {
            var entries = (hooks[ev] as? [Any]) ?? []
            entries.removeAll { commands(in: $0).contains(where: isOurs) }
            entries.append(["hooks": [["type": "command", "command": hookPath + " " + ev, "timeout": 5] as [String: Any]]])
            hooks[ev] = entries
        }
        root["hooks"] = hooks

        let dir = (hookPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try hookScript.write(toFile: hookPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
        return try file.write(root)
    }

    /// Removes only our entries; drops `hooks` entirely if that leaves it empty. Returns the backup path, if any.
    @discardableResult
    public func uninstall() throws -> String? {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return nil }
        var root = try file.load()
        guard var hooks = root["hooks"] as? [String: Any] else { return nil }
        var changed = false
        for (ev, value) in hooks {
            guard let entries = value as? [Any] else { continue }
            let kept = entries.filter { !commands(in: $0).contains(where: isOurs) }
            if kept.count != entries.count { changed = true }
            if kept.isEmpty { hooks[ev] = nil } else { hooks[ev] = kept }
        }
        guard changed else { return nil }
        if hooks.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
        return try file.write(root)
    }
}
