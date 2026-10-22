import ServiceManagement
import SwiftUI
import GladeCore

struct AboutPage: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error = ""
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
            Text("Glade is an independent project. Not affiliated with or endorsed by Anthropic.")
                .font(.system(size: 12)).foregroundColor(Theme.secondary)
            Spacer(minLength: 0)
        }
    }
}
