import AppKit
import SwiftUI
import ServiceManagement
import GladeCore

/// Settings live in a normal window. While it is open Glade behaves like a regular app (menu, Cmd-Tab);
/// when it closes it goes back to being invisible.
enum SettingsTab: String { case alerts, claudeCode = "claude-code", general }

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab: SettingsTab = .alerts
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(tab: SettingsTab? = nil) {
        if let tab = tab { SettingsNav.shared.tab = tab }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Glade Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        app.addItem(withTitle: "Quit Glade", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "Window"); fileItem.submenu = file
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
    }
}

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNav.shared

    var body: some View {
        TabView(selection: $nav.tab) {
            AlertsTab().tabItem { Label("Alerts", systemImage: "bell") }.tag(SettingsTab.alerts)
            ClaudeCodeTab().tabItem { Label("Claude Code", systemImage: "terminal") }.tag(SettingsTab.claudeCode)
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: 520, minHeight: 300)
    }
}

// MARK: alerts

struct AlertsTab: View {
    @State private var config = Config.load()

    /// Every control writes straight to config.json, the same file the CLI edits.
    private func bind<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { config[keyPath: kp] }, set: { config[keyPath: kp] = $0; config.save() })
    }

    private func row(_ text: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Play a soft chime", isOn: bind(\.chime))
            row("When Claude needs you, wait \(Int(config.waitDelay)) s before showing Mochi", bind(\.waitDelay), 0...120, step: 1)
            row("When Claude is done, wait \(Int(config.doneDelay)) s before showing Mochi", bind(\.doneDelay), 0...300, step: 5)
            row(config.giveUpAfter == 0 ? "Mochi stays until you answer" : "Mochi gives up and leaves after \(Int(config.giveUpAfter)) s",
                bind(\.giveUpAfter), 0...1800, step: 30)
            Divider()
            HStack {
                Text(snoozeDescription(config) ?? "Not snoozed").frame(maxWidth: .infinity, alignment: .leading)
                if snoozeDescription(config) != nil {
                    Button("Turn snooze off") { if let c = applySnooze("clear") { config = c } }
                } else {
                    Button("Snooze 1 hour") { if let c = applySnooze("60") { config = c } }
                }
            }
            HStack {
                Button("Show Mochi (waiting)") { sendTest(done: false) }
                Button("Show Mochi (done)") { sendTest(done: true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { config = Config.load() }
    }
}

// MARK: Claude Code

struct ClaudeCodeTab: View {
    @State private var status = HookInstaller().status()
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(statusText).font(.headline)
            Text("Glade listens to four Claude Code hooks (Notification, Stop, UserPromptSubmit, PostToolUse) in \(claudeSettingsPath). Before it changes that file it saves a backup next to it, and it only ever touches its own entries.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)
            HStack {
                Button(status == .installed ? "Reinstall hooks" : "Install hooks") { run { try HookInstaller().install() } }
                    .disabled(status == .unreadable)
                Button("Remove hooks") { run { try HookInstaller().uninstall() } }
                    .disabled(status == .notInstalled || status == .unreadable)
            }
            if !message.isEmpty {
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Text("Restart running Claude Code sessions after changing hooks.").font(.callout).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { status = HookInstaller().status() }
    }

    private var statusText: String {
        switch status {
        case .installed: return "Hooks installed"
        case .notInstalled: return "Hooks not installed"
        case .partial(let missing): return "Some hooks are missing: " + missing.joined(separator: ", ")
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

// MARK: general

struct GeneralTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Open Glade when I log in", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        error = ""
                    } catch { self.error = "Couldn't change this: \(error.localizedDescription)" }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }))
            if !error.isEmpty { Text(error).font(.callout).foregroundColor(.red) }
            Text("Settings are stored in \(supportDir)/config.json.").font(.callout).foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text("Glade is an independent project. Not affiliated with or endorsed by Anthropic.")
                .font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
