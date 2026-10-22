import XCTest
import CoreGraphics
@testable import GladeCore

final class LookStoreTests: XCTestCase {
    var dir: String!
    var store: LookStore { LookStore(userDir: dir + "/looks") }   // built-ins come from the repo's Resources/Looks

    override func setUp() { dir = NSTemporaryDirectory() + "glade-looks-" + UUID().uuidString }
    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func solid(_ w: Int, _ h: Int, rgb: (UInt8, UInt8, UInt8) = (200, 120, 90)) -> CGImage {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in stride(from: 0, to: px.count, by: 4) { px[i] = rgb.0; px[i + 1] = rgb.1; px[i + 2] = rgb.2 }
        return px.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    func testBuiltinNightForestShipsAndIsTheRightSize() throws {
        let look = store.all()[0]
        XCTAssertEqual(look.id, "night-forest")
        XCTAssertTrue(look.builtin); XCTAssertTrue(look.fireflies)
        let img = try XCTUnwrap(LookPipeline.load(store.backdropURL(look)))
        XCTAssertEqual(img.width, 480); XCTAssertEqual(img.height, 270)
    }

    func testAddListRemove() throws {
        let a = try store.add(processed: solid(480, 270), name: "  Beach  ")
        let b = try store.add(processed: solid(480, 270), name: "")
        XCTAssertEqual(a.name, "Beach")
        XCTAssertEqual(b.name, "My look")
        XCTAssertFalse(a.fireflies)
        XCTAssertEqual(store.all().map(\.id), ["night-forest", a.id, b.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backdropURL(a).path))
        try store.remove(a.id)
        XCTAssertEqual(store.all().map(\.id), ["night-forest", b.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/looks/" + a.id))
    }

    func testBuiltinCannotBeRemoved() throws {
        try store.remove("night-forest")
        try store.remove("../night-forest")
        XCTAssertEqual(store.all().first?.id, "night-forest")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backdropURL(store.all()[0]).path))
    }

    func testBrokenFoldersAreSkipped() throws {
        let good = try store.add(processed: solid(480, 270), name: "Good")
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir + "/looks/user-nojson", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dir + "/looks/user-badjson", withIntermediateDirectories: true)
        try "{nope".write(toFile: dir + "/looks/user-badjson/look.json", atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: dir + "/looks/user-nopng", withIntermediateDirectories: true)
        try JSONEncoder().encode(Look(id: "user-nopng", name: "x", fireflies: false, builtin: false))
            .write(to: URL(fileURLWithPath: dir + "/looks/user-nopng/look.json"))
        try fm.createDirectory(atPath: dir + "/looks/user-mismatch", withIntermediateDirectories: true)
        try JSONEncoder().encode(Look(id: "user-other", name: "x", fireflies: false, builtin: false))
            .write(to: URL(fileURLWithPath: dir + "/looks/user-mismatch/look.json"))
        XCTAssertEqual(store.all().map(\.id), ["night-forest", good.id])
    }

    func testMissingLookFallsBackToDefault() throws {
        XCTAssertEqual(store.look(id: "user-gone").id, "night-forest")
        let a = try store.add(processed: solid(480, 270), name: "A")
        XCTAssertEqual(store.look(id: a.id).id, a.id)
    }

    func testAddPhotoFromFileProcessesIt() throws {
        let src = URL(fileURLWithPath: dir + "/photo.png")
        try LookPipeline.writePNG(solid(1600, 900, rgb: (250, 250, 250)), to: src)
        let look = try store.add(photo: src, name: "White wall")
        let out = try XCTUnwrap(LookPipeline.load(store.backdropURL(look)))
        XCTAssertEqual(out.width, 480); XCTAssertEqual(out.height, 270)
        // a white photo must have been darkened to stay readable
        XCTAssertLessThanOrEqual(LookPipeline.worstCaseLuminance(of: out, terminalTint: 0.48), LookPipeline.maxBackgroundLuminance + 0.004)
    }

    func testNonImageIsRejectedWithoutLeavingAFolder() {
        let bad = dir + "/notes.txt"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? "hello".write(toFile: bad, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.add(photo: URL(fileURLWithPath: bad), name: "x"))
        XCTAssertEqual(store.all().count, 1)
    }
}
