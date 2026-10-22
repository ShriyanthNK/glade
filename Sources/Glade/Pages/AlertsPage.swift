import SwiftUI
import GladeCore

struct AlertsPage: View {
    @State private var config = Config.load()

    /// Every control writes straight to config.json, the same file the CLI edits.
    private func bind<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { config[keyPath: kp] }, set: { config[keyPath: kp] = $0; config.save() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Alerts", subtitle: "When Mochi shows up, and how patient he is.")
            PixelCard {
                VStack(alignment: .leading, spacing: 18) {
                    row("When Claude needs you", "Mochi waits \(Int(config.waitDelay)) s before he appears.",
                        bind(\.waitDelay), 0...120, step: 1)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    row("When Claude is done", "Mochi waits \(Int(config.doneDelay)) s before he appears.",
                        bind(\.doneDelay), 0...300, step: 5)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    row("When you don't answer",
                        config.giveUpAfter == 0 ? "Mochi stays until you do." : "Mochi gives up and leaves after \(Int(config.giveUpAfter)) s.",
                        bind(\.giveUpAfter), 0...1800, step: 30, zeroLabel: "Never")
                }
            }
            PixelCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Stay quiet while I'm already in the terminal", isOn: bind(\.smartAlerts)).toggleStyle(PixelToggleStyle())
                    Toggle("Say what Claude wants or did, not just \"waiting\"", isOn: bind(\.showDetails)).toggleStyle(PixelToggleStyle())
                    Toggle("Play a soft chime when Mochi appears", isOn: bind(\.chime)).toggleStyle(PixelToggleStyle())
                    HStack {
                        Text(snoozeDescription(config) ?? "Alerts are on.")
                            .font(.system(size: 13, design: .rounded)).foregroundColor(Theme.paper)
                        Spacer()
                        if snoozeDescription(config) != nil {
                            Button("Turn snooze off") { if let c = applySnooze("clear") { config = c } }.buttonStyle(SecondaryButtonStyle())
                        } else {
                            Button("Snooze 1 hour") { if let c = applySnooze("60") { config = c } }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            }
            HStack {
                Button("Show Mochi (waiting)") { sendTest(done: false) }.buttonStyle(SecondaryButtonStyle())
                Button("Show Mochi (done)") { sendTest(done: true) }.buttonStyle(SecondaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .onAppear { config = Config.load() }
    }

    private func row(_ title: String, _ detail: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double, zeroLabel: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.paper)
                Text(detail).font(.system(size: 12)).foregroundColor(Theme.secondary)
            }
            Spacer()
            PixelStepper(value: value, range: range, step: step, zeroLabel: zeroLabel, label: title)
        }
    }
}
