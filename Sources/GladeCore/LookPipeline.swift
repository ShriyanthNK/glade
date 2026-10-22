import CoreGraphics
import Foundation
import ImageIO

/// Turns any photo into a Mochi-style pixel backdrop: cover-crop to 16:9, scale to 480x270, reduce to a
/// limited palette with ordered dithering, then darken toward plum just enough that light terminal text
/// stays readable (WCAG 4.5:1) on top of it.
public enum LookPipeline {
    public static let width = 480
    public static let height = 270

    public struct Options: Equatable {
        /// Opacity of the terminal's own background tint that sits on top of the backdrop.
        public var terminalTint = 0.48
        /// 0 keeps the contrast minimum only; 1 adds extra darkening and softens the dither.
        public var calm = 0.0
        /// Colors per channel (6 gives 216 colors, which reads as pixel art).
        public var levels = 6
        public init() {}
    }

    public struct Result {
        public let image: CGImage
        /// How far the picture was darkened toward plum, 0...maxDarkening.
        public let darkening: Double
    }

    public static let maxDarkening = 0.85
    static let ink: [Double] = [0x2A / 255.0, 0x1A / 255.0, 0x26 / 255.0]   // the page's plum
    static let textLuminance = 0.90                                          // paper-colored terminal text
    static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

    static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Highest background luminance that still gives `textLuminance` text 4.5:1 contrast.
    public static var maxBackgroundLuminance: Double { (textLuminance + 0.05) / 4.5 - 0.05 }

    public static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,   // honor EXIF rotation
                                     kCGImageSourceThumbnailMaxPixelSize: 2048]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    public static func process(_ source: CGImage, options: Options = Options()) -> Result {
        let W = width, H = height
        // cover-crop to 16:9 and scale down
        let iw = Double(source.width), ih = Double(source.height)
        let want = Double(W) / Double(H)
        let cw = iw / ih > want ? ih * want : iw
        let ch = iw / ih > want ? ih : iw / want
        let crop = source.cropping(to: CGRect(x: ((iw - cw) / 2).rounded(.down), y: ((ih - ch) / 2).rounded(.down),
                                              width: cw.rounded(.down), height: ch.rounded(.down))) ?? source
        var px = [UInt8](repeating: 0, count: W * H * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.setFillColor(CGColor(red: ink[0], green: ink[1], blue: ink[2], alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))      // transparent sources land on plum
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: W, height: H))
        }

        // palette reduction with ordered dithering
        let levels = Double(max(2, options.levels))
        let ditherScale = 1 - 0.6 * min(1, max(0, options.calm))
        for y in 0..<H { for x in 0..<W {
            let i = (y * W + x) * 4
            let d = (bayer[y % 4][x % 4] / 16.0 - 0.5) / levels * ditherScale
            for c in 0..<3 {
                let v = min(1, max(0, Double(px[i + c]) / 255.0 + d))
                px[i + c] = UInt8((v * (levels - 1)).rounded() / (levels - 1) * 255)
            }
        }}

        // smallest darkening toward plum so the 98th-percentile pixel keeps 4.5:1 under the terminal tint
        let tint = options.terminalTint
        let need = maxBackgroundLuminance - 0.003   // margin for the subsampling and histogram binning
        // every 3rd pixel and a 4096-bin histogram keep the solver fast enough for a live slider
        let bins = 4096
        func worst(_ a: Double) -> Double {
            var hist = [Int](repeating: 0, count: bins + 1)
            var n = 0
            for p in stride(from: 0, to: W * H, by: 3) {
                var e = [0.0, 0.0, 0.0]
                for c in 0..<3 {
                    let s = Double(px[p * 4 + c]) / 255.0
                    e[c] = (s * (1 - a) + ink[c] * a) * (1 - tint) + ink[c] * tint
                }
                hist[min(bins, Int(luminance(e[0], e[1], e[2]) * Double(bins)))] += 1
                n += 1
            }
            let target = Int(Double(n) * 0.98)
            var seen = 0
            for (i, count) in hist.enumerated() { seen += count; if seen > target { return Double(i + 1) / Double(bins) } }
            return 1
        }
        var solved = 0.0
        if worst(0) > need {
            if worst(maxDarkening) > need { solved = maxDarkening }
            else {
                var lo = 0.0, hi = maxDarkening
                for _ in 0..<14 { let m = (lo + hi) / 2; if worst(m) > need { lo = m } else { hi = m } }
                solved = hi
            }
        }
        let a = min(maxDarkening, solved + 0.5 * min(1, max(0, options.calm)) * (maxDarkening - solved))
        for p in 0..<(W * H) { for c in 0..<3 {
            px[p * 4 + c] = UInt8(((Double(px[p * 4 + c]) / 255.0) * (1 - a) + ink[c] * a) * 255)
        }}

        let out = px.withUnsafeMutableBytes { buf -> CGImage in
            CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
        return Result(image: out, darkening: a)
    }

    /// 98th-percentile luminance of an image as it will look under the terminal tint (for tests and previews).
    public static func worstCaseLuminance(of image: CGImage, terminalTint: Double) -> Double {
        let W = image.width, H = image.height
        var px = [UInt8](repeating: 0, count: W * H * 4)
        px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                .draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
        }
        var ls = [Double]()
        for p in 0..<(W * H) {
            var e = [0.0, 0.0, 0.0]
            for c in 0..<3 { e[c] = (Double(px[p * 4 + c]) / 255.0) * (1 - terminalTint) + ink[c] * terminalTint }
            ls.append(luminance(e[0], e[1], e[2]))
        }
        ls.sort()
        return ls[Int(Double(ls.count) * 0.98)]
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "Glade", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "Glade", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot encode PNG"])
        }
    }
}
