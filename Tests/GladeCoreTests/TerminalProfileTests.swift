import XCTest
import AppKit
@testable import GladeCore

final class TerminalProfileTests: XCTestCase {
    func color(_ p: [String: Any], _ key: String) throws -> NSColor {
        let data = try XCTUnwrap(p[key] as? Data, key)
        let c = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        return try XCTUnwrap(c?.usingColorSpace(.sRGB), key)
    }

    func testBackgroundIsTranslucentPlumMatchingThePipelineTint() throws {
        let bg = try color(TerminalProfile.plist(), "BackgroundColor")
        XCTAssertEqual(Double(bg.alphaComponent), LookPipeline.Options().terminalTint, accuracy: 0.001)
        XCTAssertEqual(Double(bg.redComponent) * 255, 0x2A, accuracy: 1)
        XCTAssertEqual(Double(bg.greenComponent) * 255, 0x1A, accuracy: 1)
        XCTAssertEqual(Double(bg.blueComponent) * 255, 0x26, accuracy: 1)
    }

    func testTextCanBeReadAgainstTheBackdrop() throws {
        // paper text over the tinted worst-case backdrop must clear 4.5:1
        let text = try color(TerminalProfile.plist(), "TextColor")
        let l = LookPipeline.luminance(Double(text.redComponent), Double(text.greenComponent), Double(text.blueComponent))
        let ratio = (l + 0.05) / (LookPipeline.maxBackgroundLuminance + 0.05)
        XCTAssertGreaterThanOrEqual(ratio, 4.5 - 0.1)
    }

    func testHasNameSizeAndFullPalette() throws {
        let p = TerminalProfile.plist()
        XCTAssertEqual(p["name"] as? String, "Glade")
        XCTAssertEqual(p["columnCount"] as? Int, 110)
        XCTAssertEqual(p["rowCount"] as? Int, 32)
        for n in ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"] {
            _ = try color(p, "ANSI\(n)Color"); _ = try color(p, "ANSIBright\(n)Color")
        }
        XCTAssertNotNil(p["Font"] as? Data)
    }

    func testWritesAValidPropertyList() throws {
        let dir = NSTemporaryDirectory() + "glade-prof-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try TerminalProfile.write(to: dir + "/sub/Glade.terminal")
        let data = try XCTUnwrap(FileManager.default.contents(atPath: dir + "/sub/Glade.terminal"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(plist?["name"] as? String, "Glade")
        XCTAssertEqual(plist?["type"] as? String, "Window Settings")
    }

    func testParseWindowIDs() {
        XCTAssertEqual(SceneryMath.parseWindowIDs("83515, 80900\n"), [83515, 80900])
        XCTAssertEqual(SceneryMath.parseWindowIDs(""), [])
        XCTAssertEqual(SceneryMath.parseWindowIDs("missing value"), [])
        XCTAssertEqual(SceneryMath.parseWindowIDs("7"), [7])
    }

    func testCocoaRectFlipsAroundThePrimaryScreen() {
        // a 917x628 window whose top-left is at (1829, 245) on a primary display 982 tall
        let r = SceneryMath.cocoaRect(cg: CGRect(x: 1829, y: 245, width: 917, height: 628), primaryScreenHeight: 982)
        XCTAssertEqual(r, CGRect(x: 1829, y: 109, width: 917, height: 628))
        // a window above the primary display's top edge (external monitor placed higher)
        let up = SceneryMath.cocoaRect(cg: CGRect(x: 0, y: -133, width: 100, height: 50), primaryScreenHeight: 982)
        XCTAssertEqual(up.minY, 1065)
    }

    func testBackdropScaleIsAnIntegerThatCovers() {
        XCTAssertEqual(SceneryMath.backdropScale(windowWidth: 917, windowHeight: 628), 3)    // 628/270 = 2.3 -> 3
        XCTAssertEqual(SceneryMath.backdropScale(windowWidth: 480, windowHeight: 270), 1)
        XCTAssertEqual(SceneryMath.backdropScale(windowWidth: 1920, windowHeight: 300), 4)   // 1920/480 = 4
        XCTAssertEqual(SceneryMath.backdropScale(windowWidth: 10, windowHeight: 10), 1)
    }
}
