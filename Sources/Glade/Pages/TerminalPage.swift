import SwiftUI
import GladeCore

struct TerminalPage: View {
    @ObservedObject private var nav = AppNav.shared
    @State private var config = Config.load()
    @State private var message = ""
    @State private var showing = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func bind<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { config[keyPath: kp] }, set: { config[keyPath: kp] = $0; config.save() })
    }

    var body: some View {
        let look = LookStore().look(id: config.lookId)
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Terminal", subtitle: "Put your look behind the terminal you run Claude Code in. Terminal.app for now.")
            PixelCard {
                HStack(alignment: .top, spacing: 20) {
                    LookPreview(look: look, width: 300)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Glade terminal").font(Theme.title(20)).foregroundColor(Theme.paper)
                        Text("Opens Terminal.app in Hoot's colors with a see-through background. Your regular Terminal windows are left alone.")
                            .font(.system(size: 13)).foregroundColor(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        HStack {
                            Button("Open a Glade terminal") { openTerminal() }.buttonStyle(PrimaryButtonStyle())
                            Button("Change look") { nav.page = .looks }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 169)
                }
            }
            PixelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show \(look.name) behind Glade terminals", isOn: bind(\.sceneryOn)).toggleStyle(PixelToggleStyle())
                    Text(statusLine).font(.system(size: 12)).foregroundColor(Theme.secondary)
                    Text("The first time, macOS asks whether Glade may control Terminal. Allow it: that is how Glade finds your Glade terminal windows.")
                        .font(.system(size: 12)).foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundColor(Theme.paper)
            }
            Spacer(minLength: 0)
        }
        .onAppear { config = Config.load(); showing = SceneryController.shared.activeCount }
        .onReceive(ticker) { _ in showing = SceneryController.shared.activeCount }
    }

    private var statusLine: String {
        if !config.sceneryOn { return "Off. Turn it on and the scene follows each Glade terminal window." }
        if let e = SceneryController.shared.lastError { return "Can't reach Terminal: \(e)" }
        return showing == 0 ? "On. Open a Glade terminal to see it." : "Showing behind \(showing) Glade terminal window\(showing == 1 ? "" : "s")."
    }

    private func openTerminal() {
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let err = TerminalBridge.openGladeWindow()
            DispatchQueue.main.async {
                message = err ?? (config.sceneryOn ? "" : "Opened. Turn on the scene below to put \(LookStore().look(id: config.lookId).name) behind it.")
            }
        }
    }
}
