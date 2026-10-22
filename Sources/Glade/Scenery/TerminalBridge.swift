import AppKit
import GladeCore

/// Talks to Terminal.app. Everything here blocks, so call it off the main thread (except `isRunning`).
enum TerminalBridge {
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty }

    static var profilePath: String { supportDir + "/Glade.terminal" }

    /// Runs AppleScript through osascript with a timeout. Never launches Terminal itself.
    static func osascript(_ source: String, timeout: TimeInterval = 5) -> (ok: Bool, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return (false, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return (false, "timed out") }
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return p.terminationStatus == 0 ? (true, o.trimmingCharacters(in: .whitespacesAndNewlines)) : (false, e.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Window ids (the same numbers Core Graphics uses) of Terminal windows whose profile is Glade's.
    static func gladeWindowIDs() -> (ids: [Int], error: String?) {
        guard isRunning else { return ([], nil) }
        let r = osascript("""
        tell application "Terminal"
          set out to {}
          repeat with w in windows
            try
              if name of current settings of selected tab of w is "\(TerminalProfile.name)" then set end of out to id of w
            end try
          end repeat
          return out
        end tell
        """)
        return r.ok ? (SceneryMath.parseWindowIDs(r.output), nil) : ([], r.output)
    }

    /// Writes the Glade profile and opens it: Terminal imports it and opens a window using it.
    static func openGladeWindow() -> String? {
        do { try TerminalProfile.write(to: profilePath) } catch { return "Couldn't write the profile: \(error.localizedDescription)" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", profilePath]
        do { try p.run(); p.waitUntilExit() } catch { return "Couldn't open Terminal: \(error.localizedDescription)" }
        return p.terminationStatus == 0 ? nil : "Terminal didn't open the profile."
    }
}
