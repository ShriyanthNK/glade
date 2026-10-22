import AppKit
import GladeCore

/// The menu bar item: opens the Glade window, plus quick tests and snooze.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func start() {
        item.button?.image = Self.glyph()
        item.button?.toolTip = "Glade"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cfg = Config.load()

        if let s = snoozeDescription(cfg) {
            let h = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            h.isEnabled = false
            menu.addItem(h)
            menu.addItem(action("Turn snooze off", #selector(clearSnooze)))
            menu.addItem(.separator())
        }

        let open = action("Open Glade…", #selector(openGlade))
        open.keyEquivalent = "o"
        menu.addItem(open)
        menu.addItem(.separator())

        menu.addItem(action("Show Mochi (waiting)", #selector(testWaiting)))
        menu.addItem(action("Show Mochi (done)", #selector(testDone)))
        menu.addItem(.separator())

        let snooze = NSMenuItem(title: "Snooze", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, arg) in [("30 minutes", "30"), ("1 hour", "60"), ("2 hours", "120"), ("Until I turn it off", "forever")] {
            let i = action(title, #selector(snoozeFor(_:)))
            i.representedObject = arg
            sub.addItem(i)
        }
        snooze.submenu = sub
        menu.addItem(snooze)
        menu.addItem(.separator())

        let quit = action("Quit Glade", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func testWaiting() { sendTest(done: false) }
    @objc private func testDone() { sendTest(done: true) }
    @objc private func snoozeFor(_ sender: NSMenuItem) { _ = applySnooze(sender.representedObject as? String ?? "") }
    @objc private func clearSnooze() { _ = applySnooze("clear") }
    @objc private func openGlade() { AppWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Mochi's resting pose as a small colored icon, drawn from the same sprite as the pop-up.
    static func glyph() -> NSImage {
        let sprite = makeSprite(Pose(t: 0, mood: .waiting, tier: 0, look: 0))
        var minX = 32, maxX = 0, minY = 32, maxY = 0
        for y in 0..<32 { for x in 0..<32 where sprite.get(x, y) != 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let w = CGFloat(maxX - minX + 1), h = CGFloat(maxY - minY + 1)
        let side: CGFloat = 18
        let scale = side / max(w, h)
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            let ox = (side - w * scale) / 2, oy = (side - h * scale) / 2
            for y in minY...maxY { for x in minX...maxX {
                let c = sprite.get(x, y)
                guard c != 0 else { continue }
                NSColor(palette[Int(c)]).setFill()
                NSRect(x: ox + CGFloat(x - minX) * scale, y: oy + CGFloat(y - minY) * scale,
                       width: scale + 0.4, height: scale + 0.4).fill()
            } }
            return true
        }
        img.isTemplate = false
        return img
    }
}
