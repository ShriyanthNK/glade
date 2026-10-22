import GladeCore
import AppKit
import SwiftUI

func usage() {
    print("""
    glade  - Mochi, a pixel mascot that shows when Claude Code is waiting on you

      glade test [wait|done] [--age SECONDS]   show the buddy right now
      glade snooze MINUTES|forever|clear      silence the buddy
      glade settings [alerts|looks|claude-code|general]     open the settings window
      glade hooks install|uninstall|status            manage the Claude Code hooks
      glade look list|use ID|add PHOTO|remove ID      manage backdrops (add --out FILE.png just exports)
      glade hide                               hide it
      glade chime on|off                       toggle the soft chime
      glade delays WAIT DONE                   set delays in seconds (default 5 20)
      glade quit                               stop the background app
      glade snapshot FILE.png [wait|done] [AGE] [ENTER_SECONDS]
    """)
}

func ensureDaemon() -> Bool {
    if daemonRunning() { return true }
    let installed = supportDir + "/Glade.app"
    let bundle = FileManager.default.fileExists(atPath: installed) ? installed : Bundle.main.bundlePath
    let p = Process()
    if ProcessInfo.processInfo.environment["GLADE_HOME"] != nil {
        // `open` would start the app with the real environment, so an overridden home is launched directly
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    } else {
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", bundle]
    }
    try? p.run()
    for _ in 0..<30 {
        usleep(100_000)
        if daemonRunning() { return true }
    }
    return false
}

func sendEvent(_ event: String, flags: String = "", json: [String: Any] = [:]) -> Bool {
    let d = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    let bundle = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? ""
    return sendRaw("\(event)\n\(bundle)\n\(flags)\n\(String(data: d, encoding: .utf8) ?? "{}")\n")
}

@MainActor func snapshot(path: String, kind: Mood, age: Double, enter: Double?) {
    let model = BuddyModel()
    let now = Date()
    model.visible = true
    model.kind = kind
    model.message = kind == .done ? "" : "Claude needs your permission to use Bash"
    model.project = "my-project"
    model.shownAt = now.addingTimeInterval(-2)
    model.phaseStart = now.addingTimeInterval(-(enter ?? 5))
    model.ageOffset = age
    let view = BuddyRoot(model: model, fixedNow: now).frame(width: winW, height: winH).background(Color(white: 0.55))
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); exit(1) }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let statusItem = StatusItemController()

func runDaemon() {
    if daemonRunning() { exit(0) }   // single instance
    Config.migrateLegacy()
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = BuddyController()
    controller.start()
    statusItem.start()
    let server = Server()
    guard server.start({ controller.handle($0) }) else { fputs("glade: cannot bind socket\n", stderr); exit(1) }
    signal(SIGPIPE, SIG_IGN)
    app.run()
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case nil: runDaemon()
case let a? where a.hasPrefix("-"): runDaemon()
case "test":
    var kind = "wait", age = "0"
    var i = 1
    while i < args.count {
        if args[i] == "done" || args[i] == "wait" { kind = args[i] }
        else if args[i] == "--age", i + 1 < args.count { age = args[i + 1]; i += 1 }
        i += 1
    }
    guard ensureDaemon() else { print("could not start Glade.app"); exit(1) }
    let msg = kind == "done" ? "" : "Claude needs your permission to use Bash"
    var json: [String: Any] = ["session_id": "test", "cwd": FileManager.default.currentDirectoryPath]
    if !msg.isEmpty { json["message"] = msg }
    _ = sendEvent("Test", flags: "kind=\(kind == "done" ? "done" : "wait") age=\(age)", json: json)
    print("buddy sent (\(kind))")
case "snooze":
    guard let c = applySnooze(args.count > 1 ? args[1] : "") else { print("usage: glade snooze MINUTES|forever|clear"); exit(1) }
    print(c.snoozeUntil > 0 ? "snoozed" : "snooze cleared")
case "settings":
    guard ensureDaemon() else { print("could not start Glade.app"); exit(1) }
    _ = sendEvent("Settings", flags: args.count > 1 ? "tab=\(args[1])" : "")
case "look":
    let store = LookStore()
    let usage = "usage: glade look list | use ID | add PHOTO [--name NAME] [--calm 0-1] [--out FILE.png] | remove ID"
    switch args.count > 1 ? args[1] : "list" {
    case "list":
        let current = Config.load().lookId
        for l in store.all() { print((l.id == current ? "* " : "  ") + l.id + "  " + l.name + (l.builtin ? "  (built in)" : "")) }
    case "use":
        guard args.count > 2, store.all().contains(where: { $0.id == args[2] }) else { print("no such look; try: glade look list"); exit(1) }
        var c = Config.load(); c.lookId = args[2]; c.save()
        print("using " + args[2])
    case "add":
        guard args.count > 2 else { print(usage); exit(1) }
        var name = URL(fileURLWithPath: args[2]).deletingPathExtension().lastPathComponent
        var opts = LookPipeline.Options()
        var out: String?
        var i = 3
        while i + 1 < args.count {
            switch args[i] {
            case "--name": name = args[i + 1]
            case "--calm": opts.calm = min(1, max(0, Double(args[i + 1]) ?? 0))
            case "--out": out = args[i + 1]
            default: print(usage); exit(1)
            }
            i += 2
        }
        guard let src = LookPipeline.load(URL(fileURLWithPath: args[2])) else { print("couldn't read \(args[2]) as an image"); exit(1) }
        let r = LookPipeline.process(src, options: opts)
        do {
            if let out = out {
                try LookPipeline.writePNG(r.image, to: URL(fileURLWithPath: out))
                print("wrote \(out) (darkened \(Int(r.darkening * 100))%)")
            } else {
                let l = try store.add(processed: r.image, name: name)
                print("added \(l.id)  \(l.name) (darkened \(Int(r.darkening * 100))%)")
            }
        } catch { print("\(error)"); exit(1) }
    case "remove":
        guard args.count > 2 else { print(usage); exit(1) }
        do {
            try store.remove(args[2])
            var c = Config.load()
            if c.lookId == args[2] { c.lookId = LookStore.defaultId; c.save() }
            print("removed " + args[2])
        } catch { print("\(error)"); exit(1) }
    default: print(usage); exit(1)
    }
case "hooks":
    let installer = HookInstaller()
    do {
        switch args.count > 1 ? args[1] : "status" {
        case "install":
            let b = try installer.install()
            print("hooks installed" + (b.map { " (backup: \($0))" } ?? ""))
        case "uninstall":
            let b = try installer.uninstall()
            print(b.map { "hooks removed (backup: \($0))" } ?? "no Glade hooks found")
        case "status":
            switch installer.status() {
            case .installed: print("installed")
            case .notInstalled: print("not installed")
            case .partial(let m): print("partial, missing: " + m.joined(separator: ", "))
            case .unreadable: print("settings.json is not valid JSON"); exit(1)
            }
        default: print("usage: glade hooks install|uninstall|status"); exit(1)
        }
    } catch { print("\(error)"); exit(1) }
case "hide": _ = sendEvent("Hide")
case "quit": _ = sendEvent("Quit")
case "chime":
    var c = Config.load()
    c.chime = args.count > 1 && args[1] == "on"
    c.save()
    print("chime \(c.chime ? "on" : "off")")
case "delays":
    var c = Config.load()
    if args.count > 2, let w = Double(args[1]), let d = Double(args[2]) { c.waitDelay = w; c.doneDelay = d; c.save() }
    print("wait \(Config.load().waitDelay)s, done \(Config.load().doneDelay)s")
case "snapshot":
    guard args.count > 1 else { usage(); exit(1) }
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        snapshot(path: args[1], kind: args.count > 2 && args[2] == "done" ? .done : .waiting,
                 age: args.count > 3 ? Double(args[3]) ?? 0 : 0, enter: args.count > 4 ? Double(args[4]) : nil)
    }
default: usage()
}
