import SwiftUI
import GladeCore

struct ClaudeCodePage: View {
    @State private var status = HookInstaller().status()
    @State private var line = StatusLineInstaller().status()
    @State private var message = ""
    @State private var lineMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Claude Code", subtitle: "How Glade hears that Claude is done or waiting.")
            PixelCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Rectangle().fill(status == .installed ? Theme.sprout : Theme.sparkle).frame(width: 14, height: 14)
                        Text(statusText).font(Theme.title(20)).foregroundColor(Theme.paper)
                    }
                    Text("Glade listens to four Claude Code hooks (Notification, Stop, UserPromptSubmit, PostToolUse) in \(claudeSettingsPath). Before it changes that file it saves a backup next to it, and it only ever touches its own entries.")
                        .font(.system(size: 13)).foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(status == .installed ? "Reinstall hooks" : "Connect Claude Code") { run { try HookInstaller().install() } }
                            .buttonStyle(PrimaryButtonStyle()).disabled(status == .unreadable)
                        Button("Disconnect") { run { try HookInstaller().uninstall() } }
                            .buttonStyle(SecondaryButtonStyle()).disabled(status == .notInstalled || status == .unreadable)
                    }
                    if !message.isEmpty {
                        Text(message).font(.system(size: 12)).foregroundColor(Theme.paper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            statusLineCard
            Text("Restart running Claude Code sessions after changing this.")
                .font(.system(size: 12)).foregroundColor(Theme.secondary)
            Spacer(minLength: 0)
        }
        .onAppear { status = HookInstaller().status(); line = StatusLineInstaller().status() }
    }

    // MARK: status line

    private var statusLineCard: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show Mochi in Claude Code's status line", isOn: Binding(
                    get: { line == .installed },
                    set: { on in runLine { on ? try StatusLineInstaller().install() : try StatusLineInstaller().uninstall() } }))
                    .toggleStyle(PixelToggleStyle())
                    .disabled(isOtherInUse || line == .unreadable)
                VStack(alignment: .leading, spacing: 4) {
                    preview("( ^‿^)", "all good", "█░░░░░░░░░ 12%", Theme.sprout)
                    preview("( -_-)", "still here...", "███████░░░ 70%", Theme.peach)
                    preview("( >_<)", "HELLOOO?", "█████████░ 92%", Theme.alert)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.ink)
                .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview: Mochi is calm under 60 percent context, impatient from 60, worried from 85")
                Text("He gets more impatient as Claude's context window fills up.")
                    .font(.system(size: 12)).foregroundColor(Theme.secondary)
                if case .otherInUse(let cmd) = line {
                    Text("You already have a status line (\(cmd)). Replacing it is safe: Glade keeps it and puts it back when you turn Mochi's off.")
                        .font(.system(size: 12)).foregroundColor(Theme.paper).fixedSize(horizontal: false, vertical: true)
                    Button("Replace it with Mochi's") { runLine { try StatusLineInstaller().install(replacingOther: true) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if !lineMessage.isEmpty { Text(lineMessage).font(.system(size: 12)).foregroundColor(Theme.paper) }
            }
        }
    }

    private var isOtherInUse: Bool { if case .otherInUse = line { return true } else { return false } }

    private func preview(_ face: String, _ word: String, _ bar: String, _ color: Color) -> some View {
        (Text("🌱").foregroundColor(Theme.sprout) + Text(face + " ").foregroundColor(Theme.peach)
            + Text(word).bold().foregroundColor(color) + Text("  Opus · my-project  ").foregroundColor(Theme.secondary)
            + Text(bar).foregroundColor(color))
            .font(.system(size: 12, design: .monospaced))
    }

    private func runLine(_ op: () throws -> String?) {
        do {
            let backup = try op()
            lineMessage = backup.map { "Done. Backup saved to \($0)" } ?? "Done."
        } catch {
            lineMessage = "\(error)"
        }
        line = StatusLineInstaller().status()
    }

    private var statusText: String {
        switch status {
        case .installed: return "Connected"
        case .notInstalled: return "Not connected yet"
        case .partial(let missing): return "Partly connected (missing \(missing.joined(separator: ", ")))"
        case .unreadable: return "Can't read Claude Code's settings.json"
        }
    }

    private func run(_ op: () throws -> String?) {
        do {
            let backup = try op()
            message = backup.map { "Done. Backup saved to \($0)" } ?? "Done."
        } catch {
            message = "\(error)"
        }
        status = HookInstaller().status()
    }
}
