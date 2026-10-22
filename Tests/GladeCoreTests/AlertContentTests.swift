import XCTest
@testable import GladeCore

final class AlertContentTests: XCTestCase {
    // MARK: policy

    func testSuppressedWhenSessionAppIsFrontAndUserIsActive() {
        XCTAssertTrue(AlertPolicy.shouldSuppress(frontmostBundle: "com.apple.Terminal", idleSeconds: 2, sessionBundle: "com.apple.Terminal"))
    }

    func testNotSuppressedWhenUserIsIdle() {
        XCTAssertFalse(AlertPolicy.shouldSuppress(frontmostBundle: "com.apple.Terminal", idleSeconds: 60, sessionBundle: "com.apple.Terminal"))
    }

    func testNotSuppressedWhenAnotherAppIsFront() {
        XCTAssertFalse(AlertPolicy.shouldSuppress(frontmostBundle: "com.apple.Safari", idleSeconds: 1, sessionBundle: "com.apple.Terminal"))
        XCTAssertFalse(AlertPolicy.shouldSuppress(frontmostBundle: "com.googlecode.iterm2", idleSeconds: 1, sessionBundle: "com.apple.Terminal"))
    }

    func testUnknownSessionAppFallsBackToKnownTerminals() {
        XCTAssertTrue(AlertPolicy.shouldSuppress(frontmostBundle: "com.mitchellh.ghostty", idleSeconds: 1, sessionBundle: ""))
        XCTAssertFalse(AlertPolicy.shouldSuppress(frontmostBundle: "com.apple.Safari", idleSeconds: 1, sessionBundle: ""))
    }

    func testNoFrontmostAppMeansNoSuppression() {
        XCTAssertFalse(AlertPolicy.shouldSuppress(frontmostBundle: nil, idleSeconds: 0, sessionBundle: "com.apple.Terminal"))
    }

    func testBoundaryUsesActiveWithin() {
        XCTAssertTrue(AlertPolicy.shouldSuppress(frontmostBundle: "com.apple.Terminal", idleSeconds: 1.9, sessionBundle: "com.apple.Terminal", activeWithin: 2))
        XCTAssertFalse(AlertPolicy.shouldSuppress(frontmostBundle: "com.apple.Terminal", idleSeconds: 2, sessionBundle: "com.apple.Terminal", activeWithin: 2))
    }

    // MARK: tool descriptions

    func testBash() {
        XCTAssertEqual(AlertContent.describeTool(name: "Bash", input: ["command": "npm test --coverage"]), "Run: npm test --coverage")
        XCTAssertEqual(AlertContent.describeTool(name: "Bash", input: ["command": "cd x &&\n  ls   -la"]), "Run: cd x &&")
        XCTAssertEqual(AlertContent.describeTool(name: "Bash", input: [:]), "Run a command")
    }

    func testLongCommandsAreClipped() {
        let d = AlertContent.describeTool(name: "Bash", input: ["command": String(repeating: "a", count: 300)])
        XCTAssertLessThanOrEqual(d.count, AlertContent.limit)
        XCTAssertTrue(d.hasSuffix("…"))
    }

    func testFileTools() {
        XCTAssertEqual(AlertContent.describeTool(name: "Edit", input: ["file_path": "/a/b/Views.swift"]), "Edit: Views.swift")
        XCTAssertEqual(AlertContent.describeTool(name: "Write", input: ["file_path": "/a/new.md"]), "Write: new.md")
        XCTAssertEqual(AlertContent.describeTool(name: "Read", input: ["file_path": "/a/b.txt"]), "Read: b.txt")
        XCTAssertEqual(AlertContent.describeTool(name: "Edit", input: [:]), "Edit a file")
    }

    func testWebAndOthers() {
        XCTAssertEqual(AlertContent.describeTool(name: "WebFetch", input: ["url": "https://docs.example.com/x?y=1"]), "Open docs.example.com")
        XCTAssertEqual(AlertContent.describeTool(name: "WebSearch", input: ["query": "secret"]), "Search the web")
        XCTAssertEqual(AlertContent.describeTool(name: "Task", input: [:]), "Start a sub-agent")
        XCTAssertEqual(AlertContent.describeTool(name: "mcp__github__create_issue", input: [:]), "Use github: create_issue")
        XCTAssertEqual(AlertContent.describeTool(name: "Frobnicate", input: [:]), "Use Frobnicate")
        XCTAssertEqual(AlertContent.describeTool(name: "", input: [:]), "Needs your OK")
    }

    // MARK: summaries

    func testSummaryTakesTheFirstSentence() {
        XCTAssertEqual(AlertContent.summarize("Refactored the parser and fixed 3 failing tests. All 42 tests pass now."),
                       "Refactored the parser and fixed 3 failing tests.")
    }

    func testSummaryStripsMarkdown() {
        XCTAssertEqual(AlertContent.summarize("## Done\n\n**Added** the `Looks` page and wired it up. Next steps below."),
                       "Added the Looks page and wired it up.")
        XCTAssertEqual(AlertContent.summarize("## Done"), "Done")
        XCTAssertEqual(AlertContent.summarize("- **Added** the `Looks` page and wired it up. More."), "Added the Looks page and wired it up.")
    }

    func testSummarySkipsCodeFences() {
        XCTAssertEqual(AlertContent.summarize("```swift\nlet x = 1\n```\nFixed the off-by-one in the loop."), "Fixed the off-by-one in the loop.")
    }

    func testSummaryIsClipped() {
        let s = AlertContent.summarize(String(repeating: "word ", count: 80))
        XCTAssertLessThanOrEqual(s?.count ?? 999, AlertContent.limit)
        XCTAssertTrue(s?.hasSuffix("…") ?? false)
    }

    func testEmptySummaryIsNil() {
        XCTAssertNil(AlertContent.summarize(""))
        XCTAssertNil(AlertContent.summarize("  \n  "))
        XCTAssertNil(AlertContent.summarize("```\ncode only\n```"))
    }

    func testShortFirstLineKeepsGoingPastAnEarlyPeriod() {
        XCTAssertEqual(AlertContent.summarize("v1.2 is out and everything passes."), "v1.2 is out and everything passes.")
    }

    // MARK: transcript

    func testLastAssistantTextFromTranscript() throws {
        let dir = NSTemporaryDirectory() + "glade-tr-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"First answer."}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All done. Tests pass."}]}}"#,
            #"{"type":"system","content":"x"}"#,
        ]
        try lines.joined(separator: "\n").write(toFile: dir + "/t.jsonl", atomically: true, encoding: .utf8)
        XCTAssertEqual(AlertContent.lastAssistantText(transcriptPath: dir + "/t.jsonl"), "All done. Tests pass.")
    }

    func testTranscriptEdgeCases() throws {
        XCTAssertNil(AlertContent.lastAssistantText(transcriptPath: "/nonexistent/x.jsonl"))
        let dir = NSTemporaryDirectory() + "glade-tr2-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try "not json\n{broken".write(toFile: dir + "/t.jsonl", atomically: true, encoding: .utf8)
        XCTAssertNil(AlertContent.lastAssistantText(transcriptPath: dir + "/t.jsonl"))
    }

    func testLargeTranscriptOnlyReadsTheTail() throws {
        let dir = NSTemporaryDirectory() + "glade-tr3-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let filler = String(repeating: #"{"type":"user","message":{"content":"padding padding padding"}}"# + "\n", count: 20_000)   // ~1.3 MB
        let last = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Final words."}]}}"#
        try (filler + last).write(toFile: dir + "/t.jsonl", atomically: true, encoding: .utf8)
        XCTAssertEqual(AlertContent.lastAssistantText(transcriptPath: dir + "/t.jsonl"), "Final words.")
    }
}
