import XCTest
@testable import GladeCore

final class HootTests: XCTestCase {
    struct Fixture: Decodable { let frames: [Frame] }
    struct Frame: Decodable { let mood: String; let t: Double; let rows: [String] }

    func fixtures() throws -> [Frame] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/hoot-frames", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).frames
    }

    /// The Swift sprite must match the JavaScript it was ported from, pixel for pixel.
    func testMatchesTheJavaScriptFramesExactly() throws {
        let all = try fixtures()
        XCTAssertGreaterThanOrEqual(all.count, 60)
        var bad: [String] = []
        for f in all {
            let mood = try XCTUnwrap(HootMood(rawValue: f.mood))
            let got = Hoot.frame(mood, t: f.t)
            var diffs: [String] = []
            for (y, row) in f.rows.enumerated() { for (x, ch) in row.enumerated() {
                let want = UInt8(String(ch), radix: 36)!
                if got[y * 32 + x] != want { diffs.append("(\(x),\(y)) want \(want) got \(got[y * 32 + x])") }
            } }
            if !diffs.isEmpty { bad.append("\(f.mood) t=\(f.t): \(diffs.count) px differ, e.g. \(diffs.prefix(6).joined(separator: "; "))") }
        }
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n"))
    }

    func testEveryMoodLoopsSeamlessly() {
        for mood in HootMood.allCases {
            for k in stride(from: 0, to: Int(Hoot.loopSeconds * 24), by: 3) {
                let t = (Double(k) + 0.37) / 24
                XCTAssertEqual(Hoot.frame(mood, t: t), Hoot.frame(mood, t: t + Hoot.loopSeconds), "\(mood) at \(t)")
            }
        }
    }

    func testNothingTouchesTheFrameEdge() {
        for mood in HootMood.allCases {
            for k in stride(from: 0, to: Int(Hoot.loopSeconds * 24), by: 2) {
                let px = Hoot.frame(mood, t: (Double(k) + 0.37) / 24)
                for i in 0..<32 {
                    for (x, y) in [(i, 0), (i, 31), (0, i), (31, i)] { XCTAssertEqual(px[y * 32 + x], 0, "\(mood) touches the edge at \(x),\(y)") }
                }
            }
        }
    }

    func testPaletteCoversEveryIndexUsed() {
        for mood in HootMood.allCases {
            let used = Set(Hoot.frame(mood, t: 0.4))
            XCTAssertTrue(used.allSatisfy { Int($0) < Hoot.palette.count }, "\(mood)")
        }
    }

    func testMoodsLookDifferent() {
        let frames = HootMood.allCases.map { Hoot.frame($0, t: 1.01) }
        for i in 0..<frames.count { for j in (i + 1)..<frames.count { XCTAssertNotEqual(frames[i], frames[j]) } }
    }
}
