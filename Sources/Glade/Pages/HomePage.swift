import SwiftUI
import GladeCore

/// What the current look looks like behind terminal text, at the size it will actually be used.
struct LookPreview: View {
    let look: Look
    var width: CGFloat = 448
    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let img = NSImage(contentsOf: LookStore().backdropURL(look)) {
                Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fill)
            } else {
                Theme.ink
            }
            Rectangle().fill(Theme.ink.opacity(LookPipeline.Options().terminalTint))   // the terminal's own tint
            VStack(alignment: .leading, spacing: 4) {
                Text("~/my-project $ claude").foregroundColor(Theme.paper)
                Text("Claude's done, your turn.").foregroundColor(Theme.paper)
                Text("> _").foregroundColor(Theme.sparkle)
            }
            .font(.system(size: max(11, width / 34), design: .monospaced))
            .padding(width / 30)
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(look.name) look behind sample terminal text")
    }
}

struct HomePage: View {
    @ObservedObject private var nav = AppNav.shared
    @State private var config = Config.load()
    @State private var hooks = HookInstaller().status()
    private let store = LookStore()

    var body: some View {
        let look = store.look(id: config.lookId)
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Home", subtitle: "Everything Mochi is doing for you, at a glance.")
            PixelCard {
                HStack(alignment: .top, spacing: 20) {
                    LookPreview(look: look, width: 400)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your look").font(Theme.voice(11)).foregroundColor(Theme.peach)
                        Text(look.name).font(Theme.title(22)).foregroundColor(Theme.paper)
                        Text("Pick a scene, or turn any of your photos into one.")
                            .font(.system(size: 13)).foregroundColor(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Button("Change look") { nav.page = .looks }.buttonStyle(PrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 225)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                statusCard(title: "Claude Code",
                           line: hookLine, ok: hooks == .installed,
                           button: hooks == .installed ? "Open" : "Set up") { nav.page = .claudeCode }
                snoozeCard
                PixelCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Say hi").font(Theme.voice(11)).foregroundColor(Theme.peach)
                        Text("See what Mochi does.").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.paper)
                        Spacer(minLength: 4)
                        HStack {
                            Button("Waiting") { sendTest(done: false) }.buttonStyle(SecondaryButtonStyle())
                            Button("Done") { sendTest(done: true) }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .frame(height: 96)
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { refresh() }
    }

    private var hookLine: String {
        switch hooks {
        case .installed: return "Connected"
        case .notInstalled: return "Not connected yet"
        case .partial: return "Partly connected"
        case .unreadable: return "Can't read settings.json"
        }
    }

    private func refresh() { config = Config.load(); hooks = HookInstaller().status() }

    private func statusCard(title: String, line: String, ok: Bool, button: String, action: @escaping () -> Void) -> some View {
        PixelCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Theme.voice(11)).foregroundColor(Theme.peach)
                HStack(spacing: 8) {
                    Rectangle().fill(ok ? Theme.sprout : Theme.sparkle).frame(width: 10, height: 10)
                    Text(line).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.paper)
                }
                Spacer(minLength: 4)
                Button(button, action: action).buttonStyle(SecondaryButtonStyle())
            }
            .frame(height: 96)
        }
    }

    private var snoozeCard: some View {
        let s = snoozeDescription(config)
        return PixelCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alerts").font(Theme.voice(11)).foregroundColor(Theme.peach)
                HStack(spacing: 8) {
                    Rectangle().fill(s == nil ? Theme.sprout : Theme.sparkle).frame(width: 10, height: 10)
                    Text(s ?? "On").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if s == nil {
                    Button("Snooze 1 hour") { if let c = applySnooze("60") { config = c } }.buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Turn snooze off") { if let c = applySnooze("clear") { config = c } }.buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(height: 96)
        }
    }
}
