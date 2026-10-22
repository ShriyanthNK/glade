import XCTest
@testable import GladeCore

final class HookInstallerTests: XCTestCase {
    var dir: String!
    var settings: String { dir + "/claude/settings.json" }
    var hook: String { dir + "/glade/hook.sh" }
    var installer: HookInstaller { HookInstaller(settingsPath: settings, hookPath: hook) }

    override func setUp() {
        dir = NSTemporaryDirectory() + "glade-hooks-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir + "/claude", withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func write(_ json: String) { try! json.write(toFile: settings, atomically: true, encoding: .utf8) }
    func read() -> [String: Any] {
        try! JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: settings)!) as! [String: Any]
    }
    func commands(_ root: [String: Any], _ ev: String) -> [String] {
        let hooks = root["hooks"] as! [String: Any]
        return (hooks[ev] as? [[String: Any]] ?? []).flatMap { ($0["hooks"] as! [[String: Any]]).map { $0["command"] as! String } }
    }
    func backups() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir + "/claude"))?.filter { $0.contains("glade-backup") } ?? []
    }

    let other = #"""
    {"model":"sonnet","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/local/bin/other Stop"}]}],
     "PreToolUse":[{"hooks":[{"type":"command","command":"/usr/local/bin/audit"}]}]}}
    """#

    func testInstallIntoMissingFileCreatesIt() throws {
        XCTAssertEqual(installer.status(), .notInstalled)
        XCTAssertNil(try installer.install())            // nothing to back up
        XCTAssertEqual(installer.status(), .installed)
        XCTAssertEqual(commands(read(), "Stop"), [hook + " Stop"])
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hook))
        XCTAssertEqual(try String(contentsOfFile: hook, encoding: .utf8), hookScript)
    }

    func testInstallPreservesOtherSettingsAndHooks() throws {
        write(other)
        let backup = try installer.install()
        XCTAssertNotNil(backup)
        XCTAssertEqual(backups().count, 1)
        let root = read()
        XCTAssertEqual(root["model"] as? String, "sonnet")
        XCTAssertEqual(commands(root, "Stop"), ["/usr/local/bin/other Stop", hook + " Stop"])
        XCTAssertEqual(commands(root, "PreToolUse"), ["/usr/local/bin/audit"])
        for ev in HookInstaller.events { XCTAssertTrue(commands(root, ev).contains(hook + " " + ev), ev) }
    }

    func testInstallTwiceDoesNotDuplicate() throws {
        write(other)
        try installer.install()
        try installer.install()
        XCTAssertEqual(commands(read(), "Stop"), ["/usr/local/bin/other Stop", hook + " Stop"])
        XCTAssertEqual(installer.status(), .installed)
    }

    func testInstallReplacesOldClaudeBuddyHooks() throws {
        write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/Users/x/.claude-buddy/hook.sh Stop"}]}]}}"#)
        try installer.install()
        XCTAssertEqual(commands(read(), "Stop"), [hook + " Stop"])
    }

    func testUninstallRestoresOriginalHooks() throws {
        write(other)
        try installer.install()
        XCTAssertNotNil(try installer.uninstall())
        let root = read()
        XCTAssertEqual(commands(root, "Stop"), ["/usr/local/bin/other Stop"])
        XCTAssertEqual(commands(root, "PreToolUse"), ["/usr/local/bin/audit"])
        XCTAssertNil((root["hooks"] as! [String: Any])["Notification"])
        XCTAssertEqual(installer.status(), .notInstalled)
    }

    func testUninstallDropsEmptyHooksKey() throws {
        write(#"{"model":"opus"}"#)
        try installer.install()
        try installer.uninstall()
        let root = read()
        XCTAssertNil(root["hooks"])
        XCTAssertEqual(root["model"] as? String, "opus")
    }

    func testUninstallWithNothingInstalledChangesNothing() throws {
        write(other)
        XCTAssertNil(try installer.uninstall())
        XCTAssertTrue(backups().isEmpty)
    }

    func testPartialStatus() throws {
        write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(hook) Stop"}]}]}}"#)
        XCTAssertEqual(installer.status(), .partial(missing: ["Notification", "UserPromptSubmit", "PostToolUse", "PermissionRequest"]))
    }

    func testInvalidJSONThrowsAndLeavesFileAlone() {
        write("{ not json")
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try String(contentsOfFile: settings, encoding: .utf8), "{ not json")
        XCTAssertTrue(backups().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: hook))
        XCTAssertEqual(installer.status(), .unreadable)
    }

    func testEmptyFileCountsAsEmptySettings() throws {
        write("  \n")
        try installer.install()
        XCTAssertEqual(installer.status(), .installed)
    }

    func testSlashesAreNotEscaped() throws {
        try installer.install()
        let text = try String(contentsOfFile: settings, encoding: .utf8)
        XCTAssertFalse(text.contains("\\/"))
    }
}
