import XCTest
import AppKit
@testable import GladeCore

final class TerminalFontsTests: XCTestCase {
    var dir: String!
    override func setUp() {
        dir = NSTemporaryDirectory() + "glade-fonts-" + UUID().uuidString
        for d in ["src", "dest"] { try? FileManager.default.createDirectory(atPath: dir + "/" + d, withIntermediateDirectories: true) }
        for f in FontInstaller.files { try? "font-bytes-\(f)".write(toFile: dir + "/src/" + f, atomically: true, encoding: .utf8) }
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }
    var installer: FontInstaller { FontInstaller(source: dir + "/src", destination: dir + "/dest", marker: dir + "/marker.txt") }

    // MARK: choices

    func testInstalledListHasMonospacedFontsOnly() {
        let names = TerminalFonts.installed().map(\.family)
        XCTAssertTrue(names.contains("Menlo"))
        XCTAssertFalse(names.contains("Helvetica"))
        XCTAssertFalse(names.contains("Bricolage Grotesque"))
    }

    func testFavouritesComeFirst() {
        let names = TerminalFonts.installed().map(\.family)
        let menlo = names.firstIndex(of: "Menlo")!, courier = names.firstIndex(of: "Courier New")
        if let c = courier { XCTAssertLessThan(menlo, c) }
    }

    func testBundledOnlyFontNeedsInstalling() {
        BrandFonts.register()
        let jb = TerminalFonts.installed().first { $0.family == "JetBrains Mono" }
        // registered for this process from the repo's Resources/Fonts, so unless it is installed system-wide it must say so
        if let jb = jb, !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Fonts/JetBrainsMono-Medium.ttf") {
            XCTAssertTrue(jb.needsInstall)
        }
    }

    func testResolveFallsBackSafely() {
        let choices = [FontChoice(family: "Menlo", postScript: "Menlo-Regular", needsInstall: false),
                       FontChoice(family: "JetBrains Mono", postScript: "JetBrainsMono-Medium", needsInstall: true)]
        XCTAssertEqual(TerminalFonts.resolveName(family: "", choices: choices), "Menlo-Regular")                 // JB not installed yet
        XCTAssertEqual(TerminalFonts.resolveName(family: "Menlo", choices: choices), "Menlo-Regular")
        XCTAssertEqual(TerminalFonts.resolveName(family: "JetBrains Mono", choices: choices), "Menlo-Regular")   // needs install first
        XCTAssertEqual(TerminalFonts.resolveName(family: "Nope Mono", choices: choices), "Menlo-Regular")
        let installed = [FontChoice(family: "JetBrains Mono", postScript: "JetBrainsMono-Medium", needsInstall: false)]
        XCTAssertEqual(TerminalFonts.resolveName(family: "", choices: installed), "JetBrainsMono-Medium")         // automatic prefers it
    }

    // MARK: profile

    func archivedFont(_ p: [String: Any]) throws -> NSFont {
        let data = try XCTUnwrap(p["Font"] as? Data)
        return try XCTUnwrap(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: data))
    }

    func testProfileUsesTheChosenFontAndSize() throws {
        let f = try archivedFont(TerminalProfile.plist(fontName: "Monaco", fontSize: 18))
        XCTAssertEqual(f.fontName, "Monaco")
        XCTAssertEqual(f.pointSize, 18)
    }

    func testProfileFallsBackToMenloForUnknownFontsAndBadSizes() throws {
        let f = try archivedFont(TerminalProfile.plist(fontName: "Definitely-Not-A-Font", fontSize: 999))
        XCTAssertEqual(f.fontName, "Menlo-Regular")
        XCTAssertEqual(f.pointSize, 14)
    }

    // MARK: installer

    func testInstallCopiesAndRecords() throws {
        XCTAssertFalse(installer.isInstalled)
        XCTAssertEqual(try installer.install().sorted(), FontInstaller.files.sorted())
        XCTAssertTrue(installer.isInstalled)
        XCTAssertEqual(try installer.install(), [])   // second run changes nothing
    }

    func testInstallNeverOverwritesAFontTheUserHas() throws {
        let mine = FontInstaller.files[0]
        try "my own copy".write(toFile: dir + "/dest/" + mine, atomically: true, encoding: .utf8)
        let copied = try installer.install()
        XCTAssertFalse(copied.contains(mine))
        XCTAssertEqual(try String(contentsOfFile: dir + "/dest/" + mine, encoding: .utf8), "my own copy")
        // and uninstall must leave the user's own file alone
        try installer.uninstall()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/dest/" + mine))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/dest/" + FontInstaller.files[1]))
    }

    func testUninstallRemovesOnlyWhatWasInstalled() throws {
        try "unrelated".write(toFile: dir + "/dest/Other.ttf", atomically: true, encoding: .utf8)
        try installer.install()
        XCTAssertEqual(try installer.uninstall().sorted(), FontInstaller.files.sorted())
        XCTAssertFalse(installer.isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/dest/Other.ttf"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/marker.txt"))
    }

    func testUninstallWithoutAnInstallDoesNothing() throws {
        try "mine".write(toFile: dir + "/dest/" + FontInstaller.files[0], atomically: true, encoding: .utf8)
        XCTAssertEqual(try installer.uninstall(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/dest/" + FontInstaller.files[0]))
    }

    func testFullUninstallerRemovesInstalledFonts() throws {
        let support = dir + "/support"
        try FileManager.default.createDirectory(atPath: support, withIntermediateDirectories: true)
        let fi = FontInstaller(source: dir + "/src", destination: dir + "/dest", marker: support + "/installed-fonts.txt")
        try fi.install()
        let steps = try Uninstaller(supportDir: support, settingsPath: dir + "/none.json", links: [], fontsDestination: dir + "/dest").run()
        XCTAssertTrue(steps.contains { $0.contains("fonts") })
        XCTAssertFalse(fi.isInstalled)
    }
}
