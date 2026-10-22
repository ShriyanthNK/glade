import XCTest
@testable import GladeCore

final class CropRegionTests: XCTestCase {
    let iw = 4000.0, ih = 3000.0     // a 4:3 photo

    func testDefaultIsTheLargestCenteredSixteenByNine() {
        let r = CropRegion().exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(r.width, 4000, accuracy: 0.001)
        XCTAssertEqual(r.height, 2250, accuracy: 0.001)
        XCTAssertEqual(r.midX, 2000, accuracy: 0.001); XCTAssertEqual(r.midY, 1500, accuracy: 0.001)
    }

    func testAlwaysSixteenByNineAndInsideThePhoto() {
        for (w, h) in [(4000.0, 3000.0), (1000.0, 3000.0), (3000.0, 800.0), (1920.0, 1080.0)] {
            for zoom in [1.0, 1.7, 3.0, 8.0] {
                for (cx, cy) in [(0.0, 0.0), (1.0, 1.0), (0.5, 0.5), (0.2, 0.9)] {
                    let r = CropRegion(centerX: cx, centerY: cy, zoom: zoom).exactRect(imageWidth: w, imageHeight: h)
                    XCTAssertEqual(r.width / r.height, 16.0 / 9.0, accuracy: 0.0001)
                    XCTAssertGreaterThanOrEqual(r.minX, -0.0001); XCTAssertGreaterThanOrEqual(r.minY, -0.0001)
                    XCTAssertLessThanOrEqual(r.maxX, w + 0.0001); XCTAssertLessThanOrEqual(r.maxY, h + 0.0001)
                }
            }
        }
    }

    func testZoomShrinksTheCropAndIsLimited() {
        let two = CropRegion(centerX: 0.5, centerY: 0.5, zoom: 2).exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(two.width, 2000, accuracy: 0.001)
        // a 640 px wide photo can only zoom to 2x before the crop is under 320 px
        XCTAssertEqual(CropRegion.maxZoom(imageWidth: 640, imageHeight: 360), 2, accuracy: 0.001)
        XCTAssertEqual(CropRegion.maxZoom(imageWidth: 100, imageHeight: 100), 1)
        XCTAssertEqual(CropRegion.maxZoom(imageWidth: 8000, imageHeight: 4500), 8)
        let tooFar = CropRegion(centerX: 0.5, centerY: 0.5, zoom: 50).clamped(imageWidth: 640, imageHeight: 360)
        XCTAssertEqual(tooFar.zoom, 2, accuracy: 0.001)
    }

    func testPanClampsAtTheEdges() {
        let c = CropRegion(centerX: 0.5, centerY: 0.5, zoom: 2)
        let right = c.panned(dx: 99999, dy: 0, imageWidth: iw, imageHeight: ih).exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(right.maxX, iw, accuracy: 0.001)
        let up = c.panned(dx: 0, dy: -99999, imageWidth: iw, imageHeight: ih).exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(up.minY, 0, accuracy: 0.001)
        let moved = c.panned(dx: 300, dy: 0, imageWidth: iw, imageHeight: ih).exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(moved.midX, 2300, accuracy: 0.001)
    }

    func testNonsenseInputsAreSafe() {
        let c = CropRegion(centerX: .nan, centerY: .infinity, zoom: .nan).clamped(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(c.zoom, 1)
        XCTAssertTrue(c.centerX.isFinite && c.centerY.isFinite)
        let r = CropRegion().pixelRect(imageWidth: 20, imageHeight: 10)
        XCTAssertGreaterThan(r.width, 0); XCTAssertLessThanOrEqual(r.maxX, 20); XCTAssertLessThanOrEqual(r.maxY, 10)
    }

    func testDraggingACornerKeepsTheOppositeCornerFixed() {
        let start = CropRegion(centerX: 0.5, centerY: 0.5, zoom: 2)
        let r0 = start.exactRect(imageWidth: iw, imageHeight: ih)      // 1000...3000 x 1125...2250... 
        // drag the bottom-right corner toward the centre: the crop shrinks, the top-left stays
        let target = CGPoint(x: r0.minX + r0.width * 0.5, y: r0.minY + r0.height * 0.5)
        let r1 = start.resizing(.bottomRight, to: target, imageWidth: iw, imageHeight: ih).exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(r1.minX, r0.minX, accuracy: 0.5); XCTAssertEqual(r1.minY, r0.minY, accuracy: 0.5)
        XCTAssertEqual(r1.width, r0.width / 2, accuracy: 0.5)
        XCTAssertEqual(r1.width / r1.height, 16.0 / 9.0, accuracy: 0.0001)
        // and from the top-left corner the bottom-right stays
        let r2 = start.resizing(.topLeft, to: CGPoint(x: r0.maxX - r0.width * 0.4, y: r0.maxY - r0.height * 0.4),
                                imageWidth: iw, imageHeight: ih).exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(r2.maxX, r0.maxX, accuracy: 0.5); XCTAssertEqual(r2.maxY, r0.maxY, accuracy: 0.5)
        XCTAssertEqual(r2.width, r0.width * 0.4, accuracy: 0.5)
    }

    func testDraggingACornerOutwardStopsAtThePhotoAndAtZoomOne() {
        let start = CropRegion(centerX: 0.5, centerY: 0.5, zoom: 2)
        let r0 = start.exactRect(imageWidth: iw, imageHeight: ih)
        let grown = start.resizing(.bottomRight, to: CGPoint(x: 99999, y: 99999), imageWidth: iw, imageHeight: ih)
        let r = grown.exactRect(imageWidth: iw, imageHeight: ih)
        XCTAssertLessThanOrEqual(r.maxX, iw + 0.001); XCTAssertLessThanOrEqual(r.maxY, ih + 0.001)
        XCTAssertEqual(r.minX, r0.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(grown.zoom, 1)
        // dragging past the opposite corner cannot flip or collapse the crop
        let tiny = start.resizing(.bottomRight, to: CGPoint(x: r0.minX - 500, y: r0.minY - 500), imageWidth: iw, imageHeight: ih)
        XCTAssertEqual(tiny.zoom, CropRegion.maxZoom(imageWidth: iw, imageHeight: ih), accuracy: 0.001)
    }
}
