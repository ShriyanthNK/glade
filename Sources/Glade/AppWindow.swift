import AppKit
import SwiftUI
import GladeCore

enum AppPage: String, CaseIterable, Identifiable {
    case home, looks, alerts, claudeCode = "claude-code", about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .looks: return "Looks"
        case .alerts: return "Alerts"
        case .claudeCode: return "Claude Code"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .looks: return "photo.fill"
        case .alerts: return "bell.fill"
        case .claudeCode: return "terminal.fill"
        case .about: return "heart.fill"
        }
    }
}

final class AppNav: ObservableObject {
    static let shared = AppNav()
    @Published var page: AppPage = .home
}

/// The Glade app window. While it is open Glade is a regular app (Dock icon, Cmd-Tab); when it closes
/// Glade goes back to living in the menu bar.
final class AppWindowController: NSObject, NSWindowDelegate {
    static let shared = AppWindowController()
    private var window: NSWindow?

    func show(page: AppPage? = nil) {
        if let page = page { AppNav.shared.page = page }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Glade"                           // for Mission Control and accessibility; the wordmark is in the sidebar
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(red: 0x1F / 255.0, green: 0x13 / 255.0, blue: 0x20 / 255.0, alpha: 1)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AppRoot())
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        app.addItem(withTitle: "Hide Glade", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Glade", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window"); winItem.submenu = win
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
    }
}

struct AppRoot: View {
    @ObservedObject private var nav = AppNav.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(nav: nav)
            ZStack {
                Theme.deep
                Group {
                    switch nav.page {
                    case .home: HomePage()
                    case .looks: LooksPage()
                    case .alerts: AlertsPage()
                    case .claudeCode: ClaudeCodePage()
                    case .about: AboutPage()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 920, height: 620)
        .preferredColorScheme(.dark)
    }
}

struct Sidebar: View {
    @ObservedObject var nav: AppNav
    private static let forest: NSImage? = {
        let store = LookStore()
        return NSImage(contentsOf: store.backdropURL(LookStore.builtins[0]))
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ink
            if let img = Self.forest {
                Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fill)
                    .frame(width: 228, height: 620, alignment: .bottom).clipped().opacity(0.55)
                    .accessibilityHidden(true)
            }
            LinearGradient(colors: [Theme.ink, Theme.ink.opacity(0.0)], startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: 0) {
                MiniMochi(scale: 4).padding(.top, 30)
                Text("Glade").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundColor(Theme.paper)
                    .padding(.top, 2)
                Text("Mochi's on watch.").font(Theme.voice(11)).foregroundColor(Theme.peach).padding(.top, 2)
                VStack(spacing: 4) {
                    ForEach(AppPage.allCases) { page in row(page) }
                }
                .padding(.top, 26)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 228)
    }

    private func row(_ page: AppPage) -> some View {
        let selected = nav.page == page
        return Button { nav.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).frame(width: 18)
                Text(page.title)
                Spacer()
            }
            .font(.system(size: 14, weight: selected ? .bold : .medium, design: .rounded))
            .foregroundColor(selected ? Theme.outline : Theme.paper)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(selected ? Theme.peach : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
