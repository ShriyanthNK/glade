import XCTest
@testable import GladeCore

final class MessageTests: XCTestCase {
    func testFullMessage() {
        let raw = "Notification\ncom.apple.Terminal\nkind=wait age=90\n{\"session_id\":\"s1\",\"cwd\":\"/x/proj\",\"message\":\"needs OK\"}\n"
        let m = parseMessage(raw)
        XCTAssertEqual(m.event, "Notification")
        XCTAssertEqual(m.bundle, "com.apple.Terminal")
        XCTAssertEqual(m.flags, ["kind": "wait", "age": "90"])
        XCTAssertEqual(m.session, "s1")
        XCTAssertEqual(m.cwd, "/x/proj")
        XCTAssertEqual(m.text, "needs OK")
    }

    func testHookShapeWithEmptyBundleAndFlags() {
        // hook.sh sends: event, bundle (may be empty), an empty flags line, then the payload
        let m = parseMessage("Stop\n\n\n{\"session_id\":\"s2\"}\n")
        XCTAssertEqual(m.event, "Stop")
        XCTAssertEqual(m.bundle, "")
        XCTAssertTrue(m.flags.isEmpty)
        XCTAssertEqual(m.session, "s2")
        XCTAssertNil(m.text)
    }

    func testGarbageDoesNotCrash() {
        let m = parseMessage("Hide")
        XCTAssertEqual(m.event, "Hide")
        XCTAssertNil(m.session)
        XCTAssertEqual(parseMessage("").event, "")
        XCTAssertNil(parseMessage("Stop\n\n\nnot json\n").session)
    }
}
