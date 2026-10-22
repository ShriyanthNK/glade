import ServiceManagement
import SwiftUI
import GladeCore

struct AboutPage: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error = ""
    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Glade?"
        alert.informativeText = "This removes Glade's Claude Code hooks and status line (a status line it replaced is put back), your looks and settings in \(supportDir), and the glade command. Your other Claude Code settings are not touched."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try Uninstaller().run()
            NSApp.terminate(nil)
        } catch {
            self.error = "Couldn't uninstall: \(error)"
        }
    }

    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev build" }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "About", subtitle: "Glade \(version)")
            PixelCard {
                HStack(spacing: 24) {
                    MiniMochi(scale: 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mochi lives here.").font(Theme.title(20)).foregroundColor(Theme.paper)
                        Text("Glade watches Claude Code from the menu bar, pops Mochi up when it needs you, and gives your terminal a scene to sit in.")
                            .font(.system(size: 13)).foregroundColor(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            PixelCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Open Glade when I log in", isOn: Binding(
                        get: { launchAtLogin },
                        set: { on in
                            do {
                                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                error = ""
                            } catch { self.error = "Couldn't change this: \(error.localizedDescription)" }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        })).toggleStyle(PixelToggleStyle())
                    if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundColor(Theme.alert) }
                    Text("Your settings are in \(supportDir)/config.json.")
                        .font(.system(size: 12)).foregroundColor(Theme.secondary)
                }
            }
            HStack {
                Text("Glade is an independent project. Not affiliated with or endorsed by Anthropic.")
                    .font(.system(size: 12)).foregroundColor(Theme.secondary)
                Spacer()
                Button("Uninstall Glade…") { confirmUninstall() }.buttonStyle(SecondaryButtonStyle())
            }
            if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundColor(Theme.alert) }
            Spacer(minLength: 0)
        }
    }
}
