import AppKit
import XCTest
@testable import ClipShelf

final class ClipHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testNewClipGoesToTop() {
        var history = ClipHistory()
        history.add(Clip(text: "a", created: t0), limit: 10)
        history.add(Clip(text: "b", created: t0), limit: 10)
        XCTAssertEqual(history.clips.map(\.text), ["b", "a"])
    }

    func testRecopyMovesExistingClipInsteadOfDuplicating() {
        var history = ClipHistory()
        history.add(Clip(text: "a", created: t0), limit: 10)
        history.add(Clip(text: "b", created: t0), limit: 10)
        let later = t0.addingTimeInterval(60)
        history.add(Clip(text: "a", created: later), limit: 10, now: later)
        XCTAssertEqual(history.clips.map(\.text), ["a", "b"])
        XCTAssertEqual(history.clips.first?.lastUsed, later)
        XCTAssertEqual(history.clips.first?.created, t0)
    }

    func testRichAndPlainCopiesOfSameTextAreOneClip() {
        var history = ClipHistory()
        history.add(Clip(text: "hello", created: t0), limit: 10)
        history.add(Clip(text: "hello", rtf: Data("{\\rtf1 hello}".utf8), created: t0), limit: 10)
        XCTAssertEqual(history.clips.count, 1)
    }

    func testLimitTrimsOldest() {
        var history = ClipHistory()
        for value in ["1", "2", "3", "4"] {
            history.add(Clip(text: value, created: t0), limit: 3)
        }
        XCTAssertEqual(history.clips.map(\.text), ["4", "3", "2"])
    }

    func testEmptyClipIsIgnored() {
        var history = ClipHistory()
        XCTAssertFalse(history.add(Clip(created: t0), limit: 10))
        XCTAssertTrue(history.clips.isEmpty)
    }

    func testMergeSkipsDuplicatesAndSortsByLastUsed() {
        var history = ClipHistory()
        history.add(Clip(text: "current", created: t0.addingTimeInterval(100)), limit: 10)
        let imported = [
            Clip(text: "old", created: t0),
            Clip(text: "current", created: t0),
            Clip(text: "newer", created: t0.addingTimeInterval(200)),
        ]
        XCTAssertEqual(history.merge(imported, limit: 10), 2)
        XCTAssertEqual(history.clips.map(\.text), ["newer", "current", "old"])
    }

    func testMenuTitleCollapsesWhitespaceAndTruncates() {
        let clip = Clip(text: "  first line\n\n  second\tline  ", created: t0)
        XCTAssertEqual(clip.menuTitle(maxLength: 100), "first line second line")
        XCTAssertEqual(clip.menuTitle(maxLength: 10), "first line…")
    }

    func testKinds() {
        XCTAssertEqual(Clip(text: "x", created: t0).kind, .text)
        XCTAssertEqual(Clip(text: "x", rtf: Data([1]), created: t0).kind, .richText)
        XCTAssertEqual(Clip(fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")], created: t0).kind, .files)
        XCTAssertEqual(Clip(image: Data([1, 2]), created: t0).kind, .image)
        let link = URL(string: "https://example.com")!
        XCTAssertEqual(Clip(text: link.absoluteString, url: link, created: t0).kind, .url)
    }

    func testHistoryRoundTripsThroughPropertyList() throws {
        var history = ClipHistory()
        history.add(Clip(text: "a", image: Data([9]), created: t0, fromOtherDevice: true), limit: 10)
        let data = try PropertyListEncoder().encode(history)
        let decoded = try PropertyListDecoder().decode(ClipHistory.self, from: data)
        XCTAssertEqual(decoded, history)
    }
}

final class PasteboardIOTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: .init("ClipShelfTests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    func testReadsTextAndRemoteMarker() {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, PasteboardIO.remoteClipboardType], owner: nil)
        pasteboard.setString("from my other Mac", forType: .string)
        pasteboard.setData(Data(), forType: PasteboardIO.remoteClipboardType)

        let clip = PasteboardIO.readClip(from: pasteboard, storing: StoreTypes())
        XCTAssertEqual(clip?.text, "from my other Mac")
        XCTAssertEqual(clip?.fromOtherDevice, true)
    }

    func testSkipsConcealedCopies() {
        pasteboard.clearContents()
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString("secret", forType: .string)
        pasteboard.setData(Data(), forType: concealed)
        XCTAssertNil(PasteboardIO.readClip(from: pasteboard, storing: StoreTypes()))
    }

    func testRespectsStoreTypes() {
        pasteboard.clearContents()
        pasteboard.setString("text", forType: .string)
        var store = StoreTypes()
        store.text = false
        XCTAssertNil(PasteboardIO.readClip(from: pasteboard, storing: store))
    }

    func testWriteThenReadRoundTrip() {
        let clip = Clip(text: "round trip", rtf: Data("{\\rtf1 round trip}".utf8), created: Date())
        PasteboardIO.write(clip, to: pasteboard)
        let read = PasteboardIO.readClip(from: pasteboard, storing: StoreTypes())
        XCTAssertEqual(read?.text, "round trip")
        XCTAssertNotNil(read?.rtf)
    }

    func testPlainTextWriteDropsFormatting() {
        let clip = Clip(text: "plain", rtf: Data("{\\rtf1 plain}".utf8), created: Date())
        PasteboardIO.write(clip, to: pasteboard, plainText: true)
        XCTAssertEqual(pasteboard.string(forType: .string), "plain")
        XCTAssertNil(pasteboard.data(forType: .rtf))
    }
}

/// Stand-in for ClipMenu's archived `Clip` class, used to build a test archive.
@objc(ClipShelfTestOldClip)
private final class OldClip: NSObject, NSCoding {
    let text: String
    let created: Date
    init(text: String, created: Date) {
        self.text = text
        self.created = created
    }
    init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {
        coder.encode(text, forKey: "stringValue")
        coder.encode(created, forKey: "createdDate")
        coder.encode(created, forKey: "lastUsedDate")
        coder.encode(["NSStringPboardType"], forKey: "types")
    }
}

final class ClipMenuImporterTests: XCTestCase {
    func testImportsClipMenuStyleArchive() throws {
        let created = Date(timeIntervalSince1970: 1_234_567)
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("Clip", for: OldClip.self)
        archiver.encode(NSMutableArray(array: [OldClip(text: "hello", created: created)]),
                        forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        let clips = try ClipMenuImporter.clips(fromArchive: archiver.encodedData)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips.first?.text, "hello")
        XCTAssertEqual(clips.first?.created, created)
    }
}
