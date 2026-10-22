import Foundation
import GladeCore

/// Things both the CLI and the menu bar / settings window do, so they cannot drift apart.

/// Applies a snooze argument ("30", "forever", "clear"/"off") to the config. Returns nil for anything else.
func applySnooze(_ arg: String) -> Config? {
    var c = Config.load()
    if arg == "forever" { c.snoozeUntil = Date.distantFuture.timeIntervalSince1970 }
    else if arg == "clear" || arg == "off" { c.snoozeUntil = 0 }
    else if let m = Double(arg), m > 0 { c.snoozeUntil = Date().timeIntervalSince1970 + m * 60 }
    else { return nil }
    c.save()
    _ = sendEvent("Hide")
    return c
}

func snoozeDescription(_ c: Config) -> String? {
    guard c.snoozeUntil > Date().timeIntervalSince1970 else { return nil }
    if c.snoozeUntil > Date.distantFuture.timeIntervalSince1970 - 1 { return "Snoozed until you turn it off" }
    let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
    return "Snoozed until " + f.string(from: Date(timeIntervalSince1970: c.snoozeUntil))
}

/// Shows Hoot now, through the same socket path the Claude Code hooks use.
func sendTest(done: Bool, age: Double = 0) {
    var json: [String: Any] = ["session_id": "test", "cwd": FileManager.default.currentDirectoryPath]
    if done {
        json["last_assistant_message"] = "Refactored the parser and fixed 3 failing tests. All 42 tests pass now."
    } else {
        json["message"] = "Claude needs your permission to use Bash"
        json["tool_name"] = "Bash"
        json["tool_input"] = ["command": "npm test --coverage"]
    }
    _ = sendEvent("Test", flags: "kind=\(done ? "done" : "wait") age=\(age)", json: json)
}
