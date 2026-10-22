import GladeCore
import AppKit
import SwiftUI

final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

let knownTerminals = [
    "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.microsoft.VSCode",
    "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
    "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty",
    "co.zeit.hyper", "com.jetbrains.intellij", "com.jetbrains.pycharm", "dev.zed.Zed",
]

final class BuddyController {
    let model = BuddyModel()
    private var panel: BuddyPanel!
    private var pending: Timer?
    private var pendingSession: String?
    private var currentSession: String?
    private var currentBundle = ""
    private var hideTimer: Timer?
    private var tracker: Timer?
    private var screen: NSScreen?

    func start() {
        let host = ClickHostingView(rootView: BuddyRoot(model: model))
        if #available(macOS 13.0, *) { host.sizingOptions = [] }
        host.frame = NSRect(x: 0, y: 0, width: winW, height: winH)
        panel = BuddyPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        model.onActivate = { [weak self] in self?.activateTerminal() }
        model.onDismiss = { [weak self] in self?.hide() }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        tracker = t
    }

    // MARK: events

    func handle(_ m: Message) {
        let cfg = Config.load()
        switch m.event {
        case "Notification" where snoozed(cfg): break
        case "Stop" where snoozed(cfg): break
        case "Notification": schedule(.waiting, m, after: cfg.waitDelay)
        case "Stop": schedule(.done, m, after: cfg.doneDelay)
        case "Test": schedule(m.flags["kind"] == "done" ? .done : .waiting, m, after: 0)
        case "UserPromptSubmit", "PostToolUse", "SessionEnd":
            if m.session == nil || m.session == pendingSession { cancelPending() }
            if m.session == nil || m.session == currentSession { hide() }
        case "Hide": cancelPending(); hide()
        case "Quit": NSApp.terminate(nil)
        default: break
        }
    }

    private func snoozed(_ c: Config) -> Bool { c.snoozeUntil > Date().timeIntervalSince1970 }

    private func cancelPending() { pending?.invalidate(); pending = nil; pendingSession = nil }

    private func schedule(_ kind: Mood, _ m: Message, after delay: Double) {
        cancelPending()
        if delay <= 0 { show(kind, m); return }
        pendingSession = m.session
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.show(kind, m) }
        RunLoop.main.add(t, forMode: .common)
        pending = t
    }

    // MARK: show / hide

    private func show(_ kind: Mood, _ m: Message) {
        cancelPending()
        hideTimer?.invalidate(); hideTimer = nil
        model.kind = kind
        model.message = m.text ?? (kind == .waiting ? "Needs your input" : "")
        model.project = m.cwd.map { ($0 as NSString).lastPathComponent } ?? ""
        model.shownAt = Date()
        model.phaseStart = Date()
        model.exitStart = nil
        model.ageOffset = Double(m.flags["age"] ?? "") ?? 0
        model.look = 0
        model.visible = true
        currentSession = m.session
        currentBundle = m.bundle
        place(on: screenUnderMouse())
        panel.orderFrontRegardless()
        if Config.load().chime { NSSound(named: kind == .done ? "Glass" : "Tink")?.apply { $0.volume = 0.35; $0.play() } }
    }

    func hide() {
        guard model.visible, model.exitStart == nil else { return }
        model.exitStart = Date()
        currentSession = nil
        let t = Timer(timeInterval: exitDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.model.visible = false
            self.model.exitStart = nil
            self.panel.orderOut(nil)
            self.panel.ignoresMouseEvents = true
        }
        RunLoop.main.add(t, forMode: .common)
        hideTimer = t
    }

    private func activateTerminal() {
        for id in [currentBundle] + knownTerminals where !id.isEmpty {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-b", id]
                try? p.run()
                break
            }
        }
        hide()
    }

    // MARK: screen following + click-through

    private func screenUnderMouse() -> NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main
    }

    private func place(on s: NSScreen?) {
        guard let s = s else { return }
        screen = s
        let vf = s.visibleFrame
        panel.setFrame(NSRect(x: vf.maxX - winW - 4, y: vf.minY, width: winW, height: winH), display: true)
    }

    private func tick() {
        if model.visible, model.exitStart == nil {
            let c = Config.load()
            if (c.giveUpAfter > 0 && Date().timeIntervalSince(model.shownAt) > c.giveUpAfter) || snoozed(c) { hide() }
        }
        guard model.visible else { return }
        let mouse = NSEvent.mouseLocation
        if model.exitStart == nil, let s = screenUnderMouse(), s != screen {
            place(on: s)
            model.phaseStart = Date()   // pop in again on the new screen
        }
        let f = panel.frame
        let local = CGPoint(x: mouse.x - f.minX, y: f.maxY - mouse.y)
        let mascot = CGRect(x: winW - rightPad - spriteSize + 18, y: winH - spriteSize + 55, width: spriteSize - 36, height: spriteSize - 55)
        let over = mascot.contains(local) || (model.bubbleRect.width > 0 && model.bubbleRect.contains(local))
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        // eyes follow the mouse when it is close
        let cx = f.maxX - rightPad - spriteSize / 2, cyy = f.minY + 90
        let dx = mouse.x - cx, dist = hypot(dx, mouse.y - cyy)
        let look = dist < 380 ? (dx < -70 ? -1 : dx > 70 ? 1 : 0) : 0
        if look != model.look { model.look = look }
    }
}

extension NSObject {
    @discardableResult func apply(_ f: (Self) -> Void) -> Self { f(self); return self }
}
