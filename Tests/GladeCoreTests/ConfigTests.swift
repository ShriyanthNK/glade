import XCTest
@testable import GladeCore

final class ConfigTests: XCTestCase {
    var dir: String!

    override func setUp() {
        dir = NSTemporaryDirectory() + "glade-tests-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func testMissingFileGivesDefaults() {
        XCTAssertEqual(Config.load(from: dir + "/none.json"), Config())
    }

    func testRoundTrip() {
        var c = Config()
        c.chime = true; c.waitDelay = 7; c.doneDelay = 30; c.giveUpAfter = 0; c.snoozeUntil = 123
        c.lookId = "user-abc"; c.sceneryOn = true
        c.save(to: dir + "/sub/config.json")
        XCTAssertEqual(Config.load(from: dir + "/sub/config.json"), c)
    }

    func testIgnoresWrongTypes() {
        try! #"{"chime":"yes","waitDelay":"x","doneDelay":9}"#.write(toFile: dir + "/c.json", atomically: true, encoding: .utf8)
        let c = Config.load(from: dir + "/c.json")
        XCTAssertFalse(c.chime)
        XCTAssertEqual(c.waitDelay, 5)
        XCTAssertEqual(c.doneDelay, 9)
    }

    func testMigrateCopiesLegacyOnce() {
        var legacy = Config(); legacy.chime = true; legacy.waitDelay = 11
        legacy.save(to: dir + "/old/config.json")
        XCTAssertTrue(Config.migrateLegacy(from: dir + "/old/config.json", to: dir + "/new/config.json"))
        XCTAssertEqual(Config.load(from: dir + "/new/config.json"), legacy)
        // a later change to the new config must survive a second launch
        var changed = legacy; changed.waitDelay = 99
        changed.save(to: dir + "/new/config.json")
        XCTAssertFalse(Config.migrateLegacy(from: dir + "/old/config.json", to: dir + "/new/config.json"))
        XCTAssertEqual(Config.load(from: dir + "/new/config.json").waitDelay, 99)
    }

    func testMigrateWithoutLegacyDoesNothing() {
        XCTAssertFalse(Config.migrateLegacy(from: dir + "/nope.json", to: dir + "/new.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/new.json"))
    }
}
