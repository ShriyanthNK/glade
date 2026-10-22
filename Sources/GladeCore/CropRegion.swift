import CoreGraphics
import Foundation

/// Which part of a photo becomes the backdrop: a 16:9 window onto the source, set by a centre and a zoom.
/// Zoom 1 is the largest 16:9 area the photo has (what Glade picks on its own); higher zooms cut in closer.
public struct CropRegion: Equatable {
    public enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    public static let aspect = Double(LookPipeline.width) / Double(LookPipeline.height)
    /// The crop never gets narrower than this many source pixels, so a zoomed crop stays sharp enough to use.
    public static let minPixelWidth = 320.0
    public static let hardMaxZoom = 8.0

    /// Centre of the crop as a fraction of the photo (0...1 each way). Use `clamped` before trusting it.
    public var centerX = 0.5
    public var centerY = 0.5
    public var zoom = 1.0

    public init() {}
    public init(centerX: Double, centerY: Double, zoom: Double) {
        self.centerX = centerX; self.centerY = centerY; self.zoom = zoom
    }

    /// The largest 16:9 area that fits in the photo.
    public static func baseSize(imageWidth iw: Double, imageHeight ih: Double) -> CGSize {
        iw / ih > aspect ? CGSize(width: ih * aspect, height: ih) : CGSize(width: iw, height: iw / aspect)
    }

    /// How far this photo can be zoomed before the crop would drop under `minPixelWidth`.
    public static func maxZoom(imageWidth iw: Double, imageHeight ih: Double) -> Double {
        max(1, min(hardMaxZoom, baseSize(imageWidth: iw, imageHeight: ih).width / minPixelWidth))
    }

    /// Zoom within range, and a centre that keeps the whole crop inside the photo.
    public func clamped(imageWidth iw: Double, imageHeight ih: Double) -> CropRegion {
        var c = self
        c.zoom = min(max(1, zoom.isFinite ? zoom : 1), Self.maxZoom(imageWidth: iw, imageHeight: ih))
        let size = Self.baseSize(imageWidth: iw, imageHeight: ih)
        let hw = size.width / c.zoom / 2 / iw, hh = size.height / c.zoom / 2 / ih
        c.centerX = min(max(centerX.isFinite ? centerX : 0.5, hw), 1 - hw)
        c.centerY = min(max(centerY.isFinite ? centerY : 0.5, hh), 1 - hh)
        return c
    }

    /// The crop in source pixels, top-left origin, not rounded.
    public func exactRect(imageWidth iw: Double, imageHeight ih: Double) -> CGRect {
        let c = clamped(imageWidth: iw, imageHeight: ih)
        let size = Self.baseSize(imageWidth: iw, imageHeight: ih)
        let w = size.width / c.zoom, h = size.height / c.zoom
        return CGRect(x: c.centerX * iw - w / 2, y: c.centerY * ih - h / 2, width: w, height: h)
    }

    /// The crop as whole pixels, always inside the photo, for `CGImage.cropping(to:)`.
    public func pixelRect(imageWidth iw: Int, imageHeight ih: Int) -> CGRect {
        let r = exactRect(imageWidth: Double(iw), imageHeight: Double(ih))
        let w = min(Double(iw), max(16, r.width.rounded())), h = min(Double(ih), max(9, r.height.rounded()))
        let x = min(max(0, r.minX.rounded()), Double(iw) - w), y = min(max(0, r.minY.rounded()), Double(ih) - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Moves the crop by a distance in source pixels.
    public func panned(dx: Double, dy: Double, imageWidth iw: Double, imageHeight ih: Double) -> CropRegion {
        var c = clamped(imageWidth: iw, imageHeight: ih)
        c.centerX += dx / iw
        c.centerY += dy / ih
        return c.clamped(imageWidth: iw, imageHeight: ih)
    }

    /// Dragging a corner to `point` (source pixels): the opposite corner stays put and the crop keeps its 16:9 shape.
    public func resizing(_ corner: Corner, to point: CGPoint, imageWidth iw: Double, imageHeight ih: Double) -> CropRegion {
        let r = exactRect(imageWidth: iw, imageHeight: ih)
        let right = corner == .topRight || corner == .bottomRight
        let down = corner == .bottomLeft || corner == .bottomRight
        let anchor = CGPoint(x: right ? r.minX : r.maxX, y: down ? r.minY : r.maxY)
        let dx = (right ? 1.0 : -1.0) * (Double(point.x) - Double(anchor.x))
        let dy = (down ? 1.0 : -1.0) * (Double(point.y) - Double(anchor.y))
        let room = min(right ? iw - Double(anchor.x) : Double(anchor.x), (down ? ih - Double(anchor.y) : Double(anchor.y)) * Self.aspect)
        let base = Self.baseSize(imageWidth: iw, imageHeight: ih).width
        let smallest = base / Self.maxZoom(imageWidth: iw, imageHeight: ih)
        let w = min(max(max(dx, dy * Self.aspect), smallest), min(room, base))
        let h = w / Self.aspect
        let x = right ? Double(anchor.x) : Double(anchor.x) - w
        let y = down ? Double(anchor.y) : Double(anchor.y) - h
        return CropRegion(centerX: (x + w / 2) / iw, centerY: (y + h / 2) / ih, zoom: base / w)
            .clamped(imageWidth: iw, imageHeight: ih)
    }
}
