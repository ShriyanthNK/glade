import AppKit
import GladeCore

/// Draws the chosen look directly beneath every Terminal window that uses the Glade profile, so the
/// profile's translucent background shows the scene. Terminal.app has no background image, so this follows
/// the window: one borderless window per Glade terminal, ordered just below it.
final class SceneryController {
    static let shared = SceneryController()

    private var scenes: [Int: SceneWindow] = [:]
    private var ids: [Int] = []
    private var enabled = false
    private var look = LookStore().look(id: LookStore.defaultId)
    private var image: NSImage?
    private var imageKey = ""
    private let poll = DispatchQueue(label: "glade.scenery.poll")
    private var polling = false
    private(set) var activeCount = 0
    private(set) var lastError: String?
    private var tick = 0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.frame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refreshConfig() {
        let cfg = Config.load()
        enabled = cfg.sceneryOn
        let store = LookStore()
        let l = store.look(id: cfg.lookId)
        let url = store.backdropURL(l)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)??.timeIntervalSince1970 ?? 0
        let key = "\(l.id)@\(mtime)"
        if key != imageKey {
            imageKey = key
            look = l
            image = NSImage(contentsOf: url)
            scenes.values.forEach { $0.update(image: image, fireflies: l.fireflies) }
        }
    }

    private func frame() {
        tick += 1
        if tick % 20 == 1 { refreshConfig() }           // once a second
        if tick % 20 == 1, enabled, !polling {          // ask Terminal which windows are Glade's
            polling = true
            poll.async { [weak self] in
                let r = TerminalBridge.gladeWindowIDs()
                DispatchQueue.main.async { self?.ids = r.ids; self?.lastError = r.error; self?.polling = false }
            }
        }
        guard enabled, let image = image else { removeAll(); return }

        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var bounds: [Int: CGRect] = [:]
        for w in infos where (w[kCGWindowOwnerName as String] as? String) == "Terminal" && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let n = w[kCGWindowNumber as String] as? Int, ids.contains(n),
                  let d = w[kCGWindowBounds as String] as! CFDictionary?, let b = CGRect(dictionaryRepresentation: d) else { continue }
            bounds[n] = b
        }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        for id in scenes.keys where bounds[id] == nil { scenes[id]?.orderOut(nil) }
        for id in scenes.keys where !ids.contains(id) { scenes[id]?.orderOut(nil); scenes[id] = nil }
        for (id, b) in bounds {
            let scene = scenes[id] ?? SceneWindow(image: image, fireflies: look.fireflies)
            scenes[id] = scene
            scene.place(SceneryMath.cocoaRect(cg: b, primaryScreenHeight: primaryH), below: id)
        }
        activeCount = bounds.count
    }

    private func removeAll() {
        scenes.values.forEach { $0.orderOut(nil) }
        scenes.removeAll()
        activeCount = 0
    }
}

/// One scene, sized to its terminal window.
final class SceneWindow: NSWindow {
    private let view: SceneView

    init(image: NSImage?, fireflies: Bool) {
        view = SceneView(image: image, fireflies: fireflies)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        level = .normal
        collectionBehavior = [.ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(image: NSImage?, fireflies: Bool) { view.image = image; view.fireflies = fireflies }

    func place(_ rect: NSRect, below id: Int) {
        if frame != rect { setFrame(rect, display: true) }
        order(.below, relativeTo: id)
    }
}

/// Layer-backed so the GPU does the work: the backdrop is one nearest-neighbour layer and each firefly is a small
/// layer with looping position and glow animations. The CPU only moves the window to follow the terminal.
final class SceneView: NSView {
    var image: NSImage? { didSet { updateBackdrop() } }
    var fireflies: Bool { didSet { rebuildFireflies() } }
    private let backdrop = CALayer()
    private var flyLayers: [CALayer] = []
    private var laidOut = NSSize.zero
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private static let plum = NSColor(red: 0x2A / 255.0, green: 0x1A / 255.0, blue: 0x26 / 255.0, alpha: 1)

    init(image: NSImage?, fireflies: Bool) {
        self.image = image
        self.fireflies = fireflies
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Self.plum.cgColor
        backdrop.magnificationFilter = .nearest
        backdrop.minificationFilter = .nearest
        backdrop.contentsGravity = .resize
        layer?.addSublayer(backdrop)
        updateBackdrop()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateBackdrop() }

    private func updateBackdrop() {
        backdrop.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.size != laidOut else { return }
        laidOut = bounds.size
        guard let image = image else { return }
        let scale = SceneryMath.backdropScale(windowWidth: bounds.width, windowHeight: bounds.height)
        let w = image.size.width * scale, h = image.size.height * scale
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdrop.frame = CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: h)   // anchored to the bottom: trees stay in view
        CATransaction.commit()
        rebuildFireflies()
    }

    private func rebuildFireflies() {
        flyLayers.forEach { $0.removeFromSuperlayer() }
        flyLayers = []
        guard fireflies, bounds.width > 0, let image = image else { return }
        let scale = SceneryMath.backdropScale(windowWidth: bounds.width, windowHeight: bounds.height)
        let size = scale * 2
        for i in 0..<14 {
            let r = CGFloat(i) * 12.9898
            func frac(_ v: CGFloat) -> CGFloat { v - floor(v) }
            let x = frac(sin(r) * 43758.5) * bounds.width
            let y = (0.12 + 0.5 * frac(sin(r * 1.7) * 9631.1)) * bounds.height
            let fly = CALayer()
            fly.backgroundColor = NSColor(red: 1, green: 0.82, blue: 0.25, alpha: 1).cgColor
            fly.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            fly.position = CGPoint(x: x, y: y)
            fly.opacity = reduceMotion ? 0.5 : 0.1
            layer?.addSublayer(fly)
            flyLayers.append(fly)
            guard !reduceMotion else { continue }
            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = CGPoint(x: x - 30, y: y - 14)
            drift.toValue = CGPoint(x: x + 30, y: y + 14)
            drift.duration = 5 + 6 * Double(frac(sin(r * 3.1) * 2113.7))
            drift.autoreverses = true; drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drift.timeOffset = Double(frac(sin(r * 5.3) * 713.9)) * 8
            fly.add(drift, forKey: "drift")
            let glow = CABasicAnimation(keyPath: "opacity")
            glow.fromValue = 0.1; glow.toValue = 0.85
            glow.duration = 1.2 + 2.2 * Double(frac(sin(r * 7.7) * 3331.1))
            glow.autoreverses = true; glow.repeatCount = .infinity
            glow.timeOffset = Double(frac(sin(r * 2.3) * 917.3)) * 3
            fly.add(glow, forKey: "glow")
        }
        _ = image
    }
}
