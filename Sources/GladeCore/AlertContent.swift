import Foundation

/// Terminal and editor apps Claude Code commonly runs in. Used to find where to jump back to, and to tell
/// whether the user is already looking at the session.
public let knownTerminalBundles = [
    "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.microsoft.VSCode",
    "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
    "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty",
    "co.zeit.hyper", "com.jetbrains.intellij", "com.jetbrains.pycharm", "dev.zed.Zed",
]

/// Decides whether an alert would be noise because the user is already looking at the session.
public enum AlertPolicy {
    /// True when the app running the session is frontmost and the user touched the keyboard or mouse very recently.
    public static func shouldSuppress(frontmostBundle: String?, idleSeconds: Double, sessionBundle: String,
                                      activeWithin: Double = 8) -> Bool {
        guard let front = frontmostBundle, !front.isEmpty, idleSeconds < activeWithin else { return false }
        return sessionBundle.isEmpty ? knownTerminalBundles.contains(front) : front == sessionBundle
    }
}

/// Short, human text for the bubble, built from what Claude Code's hooks tell us.
public enum AlertContent {
    public static let limit = 96

    static func clip(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: { $0.isNewline || $0 == "\t" }).first.map(String.init)?
            .split(separator: " ").joined(separator: " ") ?? ""
    }

    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// What a tool call is about to do, in a few words: "Run: npm test", "Edit: Views.swift".
    public static func describeTool(name tool: String, input: [String: Any]) -> String {
        func str(_ k: String) -> String? { (input[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        switch tool {
        case "Bash": return str("command").map { "Run: " + clip(oneLine($0), limit - 5) } ?? "Run a command"
        case "Edit", "MultiEdit": return str("file_path").map { "Edit: " + name($0) } ?? "Edit a file"
        case "Write": return str("file_path").map { "Write: " + name($0) } ?? "Write a file"
        case "NotebookEdit": return str("notebook_path").map { "Edit: " + name($0) } ?? "Edit a notebook"
        case "Read": return str("file_path").map { "Read: " + name($0) } ?? "Read a file"
        case "Glob", "Grep": return "Search your files"
        case "WebFetch": return str("url").flatMap { URL(string: $0)?.host }.map { "Open " + $0 } ?? "Open a web page"
        case "WebSearch": return "Search the web"
        case "Task", "Agent": return "Start a sub-agent"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.dropFirst(5).components(separatedBy: "__")
                return parts.count >= 2 ? "Use \(parts[0]): \(parts[1..<parts.count].joined(separator: " "))" : "Use \(tool)"
            }
            return tool.isEmpty ? "Needs your OK" : "Use " + tool
        }
    }

    /// First sentence of Claude's last message, stripped of markdown and clipped to fit the bubble.
    public static func summarize(_ text: String, limit n: Int = limit) -> String? {
        var t = text
        // drop fenced code blocks, then markdown noise
        while let a = t.range(of: "```"), let b = t.range(of: "```", range: a.upperBound..<t.endIndex) { t.removeSubrange(a.lowerBound..<b.upperBound) }
        // a heading says little ("Summary", "Done"); prefer the text under it, but keep headings if that is all there is
        let raw = t.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let body = raw.filter { !$0.hasPrefix("#") }
        t = (body.isEmpty ? raw : body).joined(separator: "\n")
        t = t.replacingOccurrences(of: "[`*_#>]", with: "", options: .regularExpression)
        let lines = t.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: "^([-+]|\\d+[.)])\\s+", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        var sentence = first
        if let r = first.range(of: "[.!?](\\s|$)", options: .regularExpression), first.distance(from: first.startIndex, to: r.lowerBound) >= 12 {
            sentence = String(first[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return clip(sentence, n)
    }

    /// The text of the last assistant message in a Claude Code transcript (JSONL), reading only the file's tail.
    public static func lastAssistantText(transcriptPath: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let tail: UInt64 = 256 * 1024
        try? h.seek(toOffset: size > tail ? size - tail : 0)
        guard let data = try? h.readToEnd(), let s = String(data: data, encoding: .utf8) else { return nil }
        for line in s.split(separator: "\n").reversed() {
            guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  (o["type"] as? String) == "assistant", let msg = o["message"] as? [String: Any] else { continue }
            let text: String
            if let blocks = msg["content"] as? [[String: Any]] {
                text = blocks.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            } else if let s = msg["content"] as? String { text = s } else { continue }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }
}
