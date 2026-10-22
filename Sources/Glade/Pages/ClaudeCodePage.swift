import SwiftUI
import GladeCore

struct ClaudeCodePage: View {
    @State private var status = HookInstaller().status()
    @State private var message = ""

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
            Text("Restart running Claude Code sessions after changing this.")
                .font(.system(size: 12)).foregroundColor(Theme.secondary)
            Spacer(minLength: 0)
        }
        .onAppear { status = HookInstaller().status() }
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
