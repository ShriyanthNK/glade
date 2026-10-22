import XCTest
import CoreGraphics
@testable import GladeCore

final class LookPipelineTests: XCTestCase {
    func image(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let (r, g, b, a) = f(x, y)
            let i = (y * w + x) * 4
            let k = Double(a) / 255
            px[i] = UInt8(Double(r) * k); px[i + 1] = UInt8(Double(g) * k); px[i + 2] = UInt8(Double(b) * k); px[i + 3] = a
        } }
        return px.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }
    func solid(_ w: Int, _ h: Int, _ v: UInt8) -> CGImage { image(w, h) { _, _ in (v, v, v, 255) } }

    func pixels(_ img: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
        px.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                .draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        return px
    }

    func testOutputIsAlways480x270() {
        for (w, h) in [(1920, 1080), (1000, 3000), (300, 300), (4000, 500)] {
            let r = LookPipeline.process(solid(w, h, 128))
            XCTAssertEqual(r.image.width, 480); XCTAssertEqual(r.image.height, 270)
        }
    }

    func testBrightImageIsDarkenedUntilTextContrastHolds() {
        let opts = LookPipeline.Options()
        let r = LookPipeline.process(solid(800, 450, 255), options: opts)
        XCTAssertGreaterThan(r.darkening, 0.3)
        let worst = LookPipeline.worstCaseLuminance(of: r.image, terminalTint: opts.terminalTint)
        XCTAssertLessThanOrEqual(worst, LookPipeline.maxBackgroundLuminance + 0.004)
    }

    func testDarkImageIsLeftAlone() {
        let r = LookPipeline.process(solid(800, 450, 20))
        XCTAssertEqual(r.darkening, 0, accuracy: 0.0001)
    }

    func testBusyBrightPhotoStaysReadable() {
        // vivid gradient with bright regions, like a sunny landscape
        let img = image(960, 540) { x, y in (UInt8(255 - y / 3), UInt8(120 + x / 8), UInt8(200 - x / 8), 255) }
        let opts = LookPipeline.Options()
        let r = LookPipeline.process(img, options: opts)
        let worst = LookPipeline.worstCaseLuminance(of: r.image, terminalTint: opts.terminalTint)
        XCTAssertLessThanOrEqual(worst, LookPipeline.maxBackgroundLuminance + 0.004)
    }

    func testDarkeningIsCapped() {
        var o = LookPipeline.Options(); o.terminalTint = 0   // no help from the terminal tint
        let r = LookPipeline.process(solid(800, 450, 255), options: o)
        XCTAssertLessThanOrEqual(r.darkening, LookPipeline.maxDarkening + 0.0001)
    }

    func testCalmDarkensAndNeverExceedsCap() {
        let img = image(640, 360) { x, y in (UInt8(x % 256), UInt8(y % 256), 90, 255) }
        var calm = LookPipeline.Options(); calm.calm = 1
        let a = LookPipeline.process(img), b = LookPipeline.process(img, options: calm)
        XCTAssertGreaterThan(b.darkening, a.darkening)
        XCTAssertLessThanOrEqual(b.darkening, LookPipeline.maxDarkening + 0.0001)
    }

    func testPaletteIsLimited() {
        let img = image(960, 540) { x, y in (UInt8(x % 256), UInt8((x + y) % 256), UInt8(y % 256), 255) }
        let px = pixels(LookPipeline.process(img).image)
        var colors = Set<UInt32>()
        for i in stride(from: 0, to: px.count, by: 4) { colors.insert(UInt32(px[i]) << 16 | UInt32(px[i + 1]) << 8 | UInt32(px[i + 2])) }
        XCTAssertLessThanOrEqual(colors.count, 216)
    }

    func testTransparentSourceLandsOnPlum() {
        let px = pixels(LookPipeline.process(image(400, 225) { _, _ in (0, 0, 0, 0) }).image)
        var sum = [0, 0, 0]
        for i in stride(from: 0, to: px.count, by: 4) { for c in 0..<3 { sum[c] += Int(px[i + c]) } }
        let n = px.count / 4
        // dithering moves single pixels, but the average stays plum (not black)
        XCTAssertEqual(Double(sum[0]) / Double(n), 0x2A, accuracy: 14)
        XCTAssertEqual(Double(sum[1]) / Double(n), 0x1A, accuracy: 14)
        XCTAssertEqual(Double(sum[2]) / Double(n), 0x26, accuracy: 14)
    }

    func testDeterministic() {
        let img = image(500, 500) { x, y in (UInt8(x % 255), UInt8(y % 255), 40, 255) }
        XCTAssertEqual(pixels(LookPipeline.process(img).image), pixels(LookPipeline.process(img).image))
    }

    func testPNGRoundTrip() throws {
        let dir = NSTemporaryDirectory() + "glade-png-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let out = LookPipeline.process(solid(600, 400, 200)).image
        let url = URL(fileURLWithPath: dir + "/sub/out.png")
        try LookPipeline.writePNG(out, to: url)
        let back = LookPipeline.load(url)
        XCTAssertEqual(back?.width, 480); XCTAssertEqual(back?.height, 270)
    }
}
