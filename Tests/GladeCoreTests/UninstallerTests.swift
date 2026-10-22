import XCTest
@testable import GladeCore

final class UninstallerTests: XCTestCase {
    var dir: String!
    override func setUp() {
        dir = NSTemporaryDirectory() + "glade-un-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir + "/claude", withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: dir + "/.glade/Glade.app/Contents/MacOS", withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: dir + "/bin", withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    var settings: String { dir + "/claude/settings.json" }
    var support: String { dir + "/.glade" }

    func installEverything(otherStatusLine: String? = nil) throws {
        if let other = otherStatusLine {
            try #"{"model":"sonnet","statusLine":{"type":"command","command":"\#(other)"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/local/bin/other Stop"}]}]}}"#
                .write(toFile: settings, atomically: true, encoding: .utf8)
        } else {
            try #"{"model":"sonnet"}"#.write(toFile: settings, atomically: true, encoding: .utf8)
        }
        try HookInstaller(settingsPath: settings, hookPath: support + "/hook.sh").install()
        try StatusLineInstaller(settingsPath: settings, scriptPath: support + "/statusline.sh", previousPath: support + "/statusline.previous.json")
            .install(replacingOther: otherStatusLine != nil)
        try "bin".write(toFile: support + "/Glade.app/Contents/MacOS/glade", atomically: true, encoding: .utf8)
    }

    func read() -> [String: Any] { try! JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: settings)!) as! [String: Any] }

    func testRemovesEverythingAndKeepsUnrelatedSettings() throws {
        try installEverything()
        let link = dir + "/bin/glade"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: support + "/Glade.app/Contents/MacOS/glade")
        let steps = try Uninstaller(supportDir: support, settingsPath: settings, links: [link]).run()
        XCTAssertTrue(steps.contains { $0.contains("hooks") })
        XCTAssertTrue(steps.contains { $0.contains("status line") })
        let root = read()
        XCTAssertEqual(root["model"] as? String, "sonnet")
        XCTAssertNil(root["hooks"]); XCTAssertNil(root["statusLine"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: support))
        XCTAssertFalse(FileManager.default.fileExists(atPath: link))
    }

    func testRestoresTheStatusLineGladeReplaced() throws {
        try installEverything(otherStatusLine: "~/mine.sh")
        try Uninstaller(supportDir: support, settingsPath: settings, links: []).run()
        let root = read()
        XCTAssertEqual((root["statusLine"] as? [String: Any])?["command"] as? String, "~/mine.sh")
        let stop = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 1)   // their own Stop hook survives
    }

    func testLeavesSomeoneElsesGladeLinkAlone() throws {
        try installEverything()
        let other = dir + "/bin/other-tool"
        try "x".write(toFile: other, atomically: true, encoding: .utf8)
        let link = dir + "/bin/glade"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: other)
        try Uninstaller(supportDir: support, settingsPath: settings, links: [link]).run()
        XCTAssertTrue((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil)
    }

    func testBrokenSettingsFailsBeforeDeletingAnything() throws {
        try "{ nope".write(toFile: settings, atomically: true, encoding: .utf8)
        try "keep".write(toFile: support + "/config.json", atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Uninstaller(supportDir: support, settingsPath: settings, links: []).run())
        XCTAssertTrue(FileManager.default.fileExists(atPath: support + "/config.json"))
    }

    func testNothingInstalledIsFine() throws {
        let steps = try Uninstaller(supportDir: dir + "/never", settingsPath: dir + "/nope.json", links: []).run()
        XCTAssertTrue(steps.isEmpty)
    }
}
