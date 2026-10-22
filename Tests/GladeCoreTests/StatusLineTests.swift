import XCTest
@testable import GladeCore

final class StatusLineTests: XCTestCase {
    var dir: String!
    var settings: String { dir + "/claude/settings.json" }
    var installer: StatusLineInstaller {
        StatusLineInstaller(settingsPath: settings, scriptPath: dir + "/glade/statusline.sh", previousPath: dir + "/glade/prev.json")
    }

    override func setUp() {
        dir = NSTemporaryDirectory() + "glade-sl-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir + "/claude", withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func write(_ json: String) { try! json.write(toFile: settings, atomically: true, encoding: .utf8) }
    func read() -> [String: Any] { try! JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: settings)!) as! [String: Any] }
    func statusLineCommand() -> String? { (read()["statusLine"] as? [String: Any])?["command"] as? String }

    // MARK: installer

    func testInstallIntoEmptySettings() throws {
        XCTAssertEqual(installer.status(), .notInstalled)
        try installer.install()
        XCTAssertEqual(installer.status(), .installed)
        XCTAssertEqual(statusLineCommand(), dir + "/glade/statusline.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dir + "/glade/statusline.sh"))
    }

    func testInstallKeepsEverythingElse() throws {
        write(#"{"model":"sonnet","hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]}}"#)
        try installer.install()
        let root = read()
        XCTAssertEqual(root["model"] as? String, "sonnet")
        XCTAssertNotNil(root["hooks"])
    }

    func testRefusesToOverwriteAnotherStatusLine() throws {
        write(#"{"statusLine":{"type":"command","command":"~/mine.sh"}}"#)
        XCTAssertEqual(installer.status(), .otherInUse(command: "~/mine.sh"))
        XCTAssertThrowsError(try installer.install()) { XCTAssertEqual($0 as? StatusLineError, .otherInUse("~/mine.sh")) }
        XCTAssertEqual(statusLineCommand(), "~/mine.sh")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/glade/statusline.sh"))
    }

    func testReplaceThenUninstallRestoresTheOldOne() throws {
        write(#"{"statusLine":{"type":"command","command":"~/mine.sh","padding":2}}"#)
        try installer.install(replacingOther: true)
        XCTAssertEqual(installer.status(), .installed)
        try installer.uninstall()
        let sl = read()["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["command"] as? String, "~/mine.sh")
        XCTAssertEqual(sl?["padding"] as? Int, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/glade/prev.json"))
    }

    func testUninstallWithNoPreviousRemovesTheKey() throws {
        try installer.install()
        try installer.uninstall()
        XCTAssertNil(read()["statusLine"])
    }

    func testUninstallLeavesSomeoneElsesAlone() throws {
        write(#"{"statusLine":{"type":"command","command":"~/mine.sh"}}"#)
        XCTAssertNil(try installer.uninstall())
        XCTAssertEqual(statusLineCommand(), "~/mine.sh")
    }

    func testInstallTwiceIsFine() throws {
        try installer.install(); try installer.install()
        XCTAssertEqual(installer.status(), .installed)
    }

    func testInvalidJSONThrowsAndChangesNothing() {
        write("{ nope")
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try String(contentsOfFile: settings, encoding: .utf8), "{ nope")
        XCTAssertEqual(installer.status(), .unreadable)
    }

    // MARK: the script itself

    func run(_ json: String) throws -> String {
        let path = dir + "/glade/statusline.sh"
        try installer.install()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [path]
        let inp = Pipe(), out = Pipe()
        p.standardInput = inp; p.standardOutput = out
        try p.run()
        inp.fileHandleForWriting.write(Data(json.utf8)); inp.fileHandleForWriting.closeFile()
        p.waitUntilExit()
        let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return raw.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    func payload(_ pct: String) -> String {
        #"{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x/my-project"},"context_window":{"used_percentage":\#(pct)}}"#
    }

    func testCalmImpatientAndWorried() throws {
        XCTAssertTrue(try run(payload("12")).contains("all good"))
        XCTAssertTrue(try run(payload("59.9")).contains("all good"))
        XCTAssertTrue(try run(payload("60")).contains("still here..."))
        XCTAssertTrue(try run(payload("84")).contains("still here..."))
        XCTAssertTrue(try run(payload("92")).contains("HELLOOO?"))
    }

    func testShowsModelDirectoryAndBar() throws {
        let line = try run(payload("30"))
        XCTAssertTrue(line.contains("Opus"))
        XCTAssertTrue(line.contains("my-project"))
        XCTAssertTrue(line.contains("███░░░░░░░ 30%"))
    }

    func testMissingFieldsStillRender() throws {
        let line = try run("{}")
        XCTAssertTrue(line.contains("Claude"))
        XCTAssertTrue(line.contains("all good"))
        XCTAssertTrue(line.contains("0%"))
        XCTAssertTrue(try run(#"{"context_window":{"used_percentage":null}}"#).contains("0%"))
    }

    func testBarNeverOverflows() throws {
        XCTAssertTrue(try run(payload("140")).contains("██████████ 140%"))
    }
}
