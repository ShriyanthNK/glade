import SwiftUI
import GladeCore

/// Pick a monospaced font and size for Glade terminals, with a live preview; applies to the Glade profile in Terminal.
struct TerminalFontCard: View {
    @State private var config = Config.load()
    @State private var choices: [FontChoice] = []
    @State private var message = ""
    @State private var installed = FontInstaller().isInstalled

    private func save() { config.save() }

    private var selected: FontChoice? { choices.first { $0.family == config.terminalFont } }
    private var needsInstall: Bool { selected?.needsInstall ?? false }
    private var postScript: String { TerminalFonts.resolveName(family: config.terminalFont, choices: choices) }

    /// The preview shows what was asked for even before it is installed (Glade carries JetBrains Mono itself).
    private var previewFont: Font {
        if let s = selected { return .custom(s.postScript, size: config.terminalFontSize) }
        return .custom(postScript, size: config.terminalFontSize)
    }

    var body: some View {
        PixelCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Terminal font").font(Theme.title(20)).foregroundColor(Theme.paper)
                HStack(spacing: 16) {
                    Picker("Font", selection: Binding(get: { config.terminalFont }, set: { config.terminalFont = $0; save() })) {
                        Text("Automatic").tag("")
                        ForEach(choices) { c in Text(c.family + (c.needsInstall ? " (needs installing)" : "")).tag(c.family) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 260)
                    PixelStepper(value: Binding(get: { config.terminalFontSize }, set: { config.terminalFontSize = $0; save() }),
                                 range: TerminalFonts.sizeRange, step: 1, unit: "pt", label: "Font size")
                    Spacer(minLength: 0)
                }
                Text("~/my-project $ claude\n> refactor the auth middleware")
                    .font(previewFont).foregroundColor(Theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.ink).overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
                    .accessibilityLabel("Preview of the terminal font")
                HStack(spacing: 12) {
                    Button("Apply to Glade terminals") { apply() }.buttonStyle(PrimaryButtonStyle())
                    if needsInstall || (config.terminalFont == "JetBrains Mono" && !installed) {
                        Button("Install JetBrains Mono") { install() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                Text(message.isEmpty ? "Automatic uses JetBrains Mono once it is installed, otherwise Menlo. Terminal can only use fonts installed on your Mac." : message)
                    .font(.system(size: 12)).foregroundColor(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { config = Config.load(); choices = TerminalFonts.installed(); installed = FontInstaller().isInstalled }
    }

    private func apply() {
        let name = postScript, size = config.terminalFontSize
        message = "Applying…"
        DispatchQueue.global(qos: .userInitiated).async {
            let err = TerminalBridge.applyFont(postScript: name, size: size)
            DispatchQueue.main.async { message = err ?? "Applied. Open Glade terminals changed right away." }
        }
    }

    private func install() {
        do {
            let copied = try FontInstaller().install()
            installed = true
            choices = TerminalFonts.installed()
            message = copied.isEmpty ? "JetBrains Mono was already installed." : "Installed JetBrains Mono for your user account. If Terminal doesn't list it yet, restart Terminal."
        } catch {
            message = "Couldn't install the font: \(error.localizedDescription)"
        }
    }
}
