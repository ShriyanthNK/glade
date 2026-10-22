import GladeCore
import AppKit

func sendEvent(_ event: String, flags: String = "", json: [String: Any] = [:]) -> Bool {
    let d = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    let bundle = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? ""
    return sendRaw("\(event)\n\(bundle)\n\(flags)\n\(String(data: d, encoding: .utf8) ?? "{}")\n")
}

let statusItem = StatusItemController()
let appDelegate = AppDelegate()

func runDaemon() {
    if daemonRunning() { exit(0) }   // single instance
    Config.migrateLegacy()
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.delegate = appDelegate
    let controller = BuddyController()
    controller.start()
    statusItem.start()
    SceneryController.shared.start()
    let server = Server()
    guard server.start({ controller.handle($0) }) else { fputs("glade: cannot bind socket\n", stderr); exit(1) }
    signal(SIGPIPE, SIG_IGN)
    app.run()
}

BrandFonts.register()
runDaemon()
