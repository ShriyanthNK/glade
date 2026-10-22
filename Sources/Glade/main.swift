import GladeCore
import AppKit
import SwiftUI

func usage() {
    print("""
    glade  - Mochi, a pixel mascot that shows when Claude Code is waiting on you

      glade test [wait|done] [--age SECONDS]   show the buddy right now
      glade snooze MINUTES|forever|clear      silence the buddy
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

func runDaemon() {
    if daemonRunning() { exit(0) }   // single instance
    Config.migrateLegacy()
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = BuddyController()
    controller.start()
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
    var c = Config.load()
    let a = args.count > 1 ? args[1] : ""
    if a == "forever" { c.snoozeUntil = Date.distantFuture.timeIntervalSince1970 }
    else if a == "clear" || a == "off" { c.snoozeUntil = 0 }
    else if let m = Double(a) { c.snoozeUntil = Date().timeIntervalSince1970 + m * 60 }
    else { print("usage: glade snooze MINUTES|forever|clear"); exit(1) }
    c.save()
    _ = sendEvent("Hide")
    print(c.snoozeUntil > 0 ? "snoozed" : "snooze cleared")
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
