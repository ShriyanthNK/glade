import XCTest
import AppKit
@testable import GladeCore

final class BrandFontsTests: XCTestCase {
    func testFontsAreBundledWithTheirLicenses() throws {
        let dir = BrandFonts.directory()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        XCTAssertEqual(files.filter { $0.hasSuffix(".ttf") }.count, BrandFonts.all.count)
        for name in ["OFL-BricolageGrotesque.txt", "OFL-PixelifySans.txt", "OFL-JetBrainsMono.txt"] {
            XCTAssertTrue(files.contains(name), "license text \(name) must ship with the fonts")
        }
    }

    func testEveryBrandFontRegistersAndResolvesByName() {
        XCTAssertEqual(BrandFonts.register(), BrandFonts.all.count)
        for name in BrandFonts.all {
            let f = NSFont(name: name, size: 14)
            XCTAssertNotNil(f, "\(name) should resolve after registration")
            XCTAssertEqual(f?.fontName, name)
        }
    }

    func testRegisteringTwiceIsHarmless() {
        BrandFonts.register(); BrandFonts.register()
        XCTAssertNotNil(NSFont(name: BrandFonts.display, size: 20))
    }

    func testMissingDirectoryRegistersNothing() {
        XCTAssertEqual(BrandFonts.register(from: "/nonexistent/fonts"), 0)
    }

    func testMonospacedFontsHaveEqualAdvances() throws {
        BrandFonts.register()
        let f = try XCTUnwrap(NSFont(name: BrandFonts.voice, size: 20))
        XCTAssertTrue(f.isFixedPitch)
    }
}
