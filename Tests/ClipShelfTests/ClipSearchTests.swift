import Foundation
import XCTest
@testable import ClipShelf

final class ClipSearchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func text(_ string: String) -> Clip {
        Clip(text: string, created: now)
    }

    func testBlankQueryHasNoTerms() {
        XCTAssertEqual(ClipSearch.terms("   \n "), [])
        XCTAssertEqual(ClipSearch.terms("  foo   Bar "), ["foo", "Bar"])
    }

    func testMatchesIgnoringCaseAndKeepsHistoryPosition() {
        let clips = [text("first thing"), text("Hello World"), text("other"), text("hello again")]
        let results = ClipSearch.search(clips, query: "HELLO")
        XCTAssertEqual(results.map(\.index), [1, 3])
        XCTAssertEqual(results.map(\.id), [clips[1].id, clips[3].id])
    }

    func testEveryTermMustMatchInAnyOrder() {
        let clips = [text("invoice for March"), text("March budget"), text("invoice draft")]
        XCTAssertEqual(ClipSearch.search(clips, query: "march invoice").map(\.index), [0])
    }

    func testIgnoresDiacritics() {
        let clips = [text("Meet at the Café"), text("coffee")]
        XCTAssertEqual(ClipSearch.search(clips, query: "cafe").map(\.index), [0])
    }

    func testSearchesURLsAndFileNames() {
        let clips = [
            Clip(url: URL(string: "https://example.com/report")!, created: now),
            Clip(fileURLs: [URL(fileURLWithPath: "/Users/me/Documents/Quarterly Plan.pdf")], created: now),
            Clip(image: Data([1, 2, 3]), created: now),
        ]
        XCTAssertEqual(ClipSearch.search(clips, query: "example.com").map(\.index), [0])
        XCTAssertEqual(ClipSearch.search(clips, query: "quarterly").map(\.index), [1])
        XCTAssertEqual(ClipSearch.search(clips, query: "users").map(\.index), [],
                       "Only file names are searched, not their folders")
    }

    func testExcerptShowsTheMatchWhenItIsDeepInTheText() throws {
        let long = String(repeating: "filler ", count: 40) + "the secret password hint" + String(repeating: " tail", count: 40)
        let result = try XCTUnwrap(ClipSearch.search([text(long)], query: "secret", excerptLength: 40).first)

        XCTAssertTrue(result.excerpt.hasPrefix("…"), result.excerpt)
        XCTAssertTrue(result.excerpt.hasSuffix("…"), result.excerpt)
        XCTAssertLessThanOrEqual(result.excerpt.count, 42)
        let highlighted = try XCTUnwrap(result.highlights.first)
        XCTAssertEqual((result.excerpt as NSString).substring(with: highlighted), "secret")
    }

    func testExcerptOfShortTextIsTheWholeLineWithEveryTermHighlighted() throws {
        let result = try XCTUnwrap(ClipSearch.search([text("Foo\n  bar foo")], query: "foo bar").first)
        XCTAssertEqual(result.excerpt, "Foo bar foo")
        let words = result.highlights.map { (result.excerpt as NSString).substring(with: $0) }
        XCTAssertEqual(words.sorted(), ["Foo", "bar", "foo"])
    }
}

final class MenuLayoutTests: XCTestCase {
    func testFolderMatchesTheMenuGrouping() {
        // 10 inline, then folders of 10: 11–20, 21–30, …, last one partial.
        XCTAssertNil(MenuLayout.folder(containing: 9, inlineCount: 10, folderSize: 10, total: 95))
        XCTAssertEqual(MenuLayout.folder(containing: 10, inlineCount: 10, folderSize: 10, total: 95), 11...20)
        XCTAssertEqual(MenuLayout.folder(containing: 36, inlineCount: 10, folderSize: 10, total: 95), 31...40)
        XCTAssertEqual(MenuLayout.folder(containing: 94, inlineCount: 10, folderSize: 10, total: 95), 91...95)
        XCTAssertNil(MenuLayout.folder(containing: 95, inlineCount: 10, folderSize: 10, total: 95))
    }
}

final class MenuPlacementTests: XCTestCase {
    // A 1440×900 screen whose visible area excludes a 25 pt menu bar and a 60 pt Dock.
    private let visible = NSRect(x: 0, y: 60, width: 1440, height: 815)
    private let size = NSSize(width: 300, height: 500)

    func testKeepsThePointerAsTopLeftWhenTheMenuFits() {
        XCTAssertEqual(MenuLayout.popUpOrigin(pointer: NSPoint(x: 100, y: 800), menuSize: size, visibleFrame: visible),
                       NSPoint(x: 100, y: 800))
    }

    func testMovesUpNearTheBottomOfTheScreen() {
        // Pointer 100 pt above the Dock: the 500 pt menu must rise so its bottom sits on the visible area.
        XCTAssertEqual(MenuLayout.popUpOrigin(pointer: NSPoint(x: 100, y: 160), menuSize: size, visibleFrame: visible),
                       NSPoint(x: 100, y: 560))
    }

    func testMovesLeftNearTheRightEdge() {
        XCTAssertEqual(MenuLayout.popUpOrigin(pointer: NSPoint(x: 1400, y: 800), menuSize: size, visibleFrame: visible),
                       NSPoint(x: 1140, y: 800))
    }

    func testMenuTallerThanTheScreenStartsAtTheTop() {
        let tall = NSSize(width: 300, height: 2000)
        XCTAssertEqual(MenuLayout.popUpOrigin(pointer: NSPoint(x: 100, y: 160), menuSize: tall, visibleFrame: visible),
                       NSPoint(x: 100, y: 875))
    }
}
