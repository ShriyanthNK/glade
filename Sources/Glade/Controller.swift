import GladeCore
import AppKit
import SwiftUI

final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

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
    private var details: [String: String] = [:]   // what Claude wants, by session, from PermissionRequest
    private var currentForced = false              // shown by `glade test`: never auto-hidden or suppressed

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
        case "Notification" where snoozed(cfg), "Stop" where snoozed(cfg), "PermissionRequest" where snoozed(cfg): break
        case "PermissionRequest":
            if let s = m.session, let d = m.detail { details[s] = d }
            schedule(.waiting, m, after: cfg.waitDelay)
        case "Notification": schedule(.waiting, m, after: cfg.waitDelay)
        case "Stop": schedule(.done, m, after: cfg.doneDelay)
        case "Test": schedule(m.flags["kind"] == "done" ? .done : .waiting, m, after: 0, force: true)
        case "UserPromptSubmit", "PostToolUse", "SessionEnd":
            if m.session == nil || m.session == pendingSession { cancelPending() }
            if let s = m.session { details[s] = nil } else { details.removeAll() }
            if m.session == nil || m.session == currentSession { hide() }
        case "Hide": cancelPending(); hide()
        case "Settings", "Open": AppWindowController.shared.show(page: m.flags["tab"].flatMap(AppPage.init(rawValue:)))
        case "Quit": NSApp.terminate(nil)
        default: break
        }
    }

    private func snoozed(_ c: Config) -> Bool { c.snoozeUntil > Date().timeIntervalSince1970 }

    private func cancelPending() { pending?.invalidate(); pending = nil; pendingSession = nil }

    private func schedule(_ kind: Mood, _ m: Message, after delay: Double, force: Bool = false) {
        cancelPending()
        pendingSession = m.session
        if delay <= 0 { attempt(kind, m, force: force); return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.attempt(kind, m, force: force) }
        RunLoop.main.add(t, forMode: .common)
        pending = t
    }

    /// Shows Hoot unless the user is already looking at the session. While they are, check again every few
    /// seconds: the hooks cancel this as soon as Claude moves on, and if they look away it still gets through.
    private func attempt(_ kind: Mood, _ m: Message, force: Bool) {
        if !force, Config.load().smartAlerts, userIsLookingAtSession(m.bundle, activeWithin: 8) {
            let t = Timer(timeInterval: 3, repeats: false) { [weak self] _ in self?.attempt(kind, m, force: false) }
            RunLoop.main.add(t, forMode: .common)
            pending = t
            return
        }
        show(kind, m, forced: force)
    }

    private func userIsLookingAtSession(_ bundle: String, activeWithin: Double) -> Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return AlertPolicy.shouldSuppress(frontmostBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                          idleSeconds: idle, sessionBundle: bundle, activeWithin: activeWithin)
    }

    // MARK: show / hide

    private func show(_ kind: Mood, _ m: Message, forced: Bool = false) {
        cancelPending()
        currentForced = forced
        hideTimer?.invalidate(); hideTimer = nil
        model.kind = kind
        let cfg = Config.load()
        let content: String? = cfg.showDetails ? (kind == .waiting ? (m.session.flatMap { details[$0] } ?? m.detail) : m.summary) : nil
        model.message = content ?? m.text ?? (kind == .waiting ? "Needs your input" : "")
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
        if cfg.chime { NSSound(named: kind == .done ? "Glass" : "Tink")?.apply { $0.volume = 0.35; $0.play() } }
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
        for id in [currentBundle] + knownTerminalBundles where !id.isEmpty {
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
            // they came to the terminal and are typing: they have seen it
            else if c.smartAlerts, !currentForced, Date().timeIntervalSince(model.shownAt) > 3,
                    userIsLookingAtSession(currentBundle, activeWithin: 2) { hide() }
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
