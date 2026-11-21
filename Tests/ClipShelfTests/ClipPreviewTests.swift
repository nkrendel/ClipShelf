import AppKit
import XCTest
@testable import ClipShelf

@MainActor
final class ClipPreviewTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 60, width: 1440, height: 815)
    private let size = NSSize(width: 200, height: 150)

    func testLargeImagesShrinkToFitKeepingTheirShape() {
        XCTAssertEqual(ClipPreview.fittedSize(NSSize(width: 1920, height: 1080), within: NSSize(width: 360, height: 360)),
                       NSSize(width: 360, height: 203))
        XCTAssertEqual(ClipPreview.fittedSize(NSSize(width: 300, height: 1200), within: NSSize(width: 360, height: 360)),
                       NSSize(width: 90, height: 360))
    }

    func testSmallImagesAreNotEnlarged() {
        XCTAssertEqual(ClipPreview.fittedSize(NSSize(width: 64, height: 48), within: NSSize(width: 360, height: 360)),
                       NSSize(width: 64, height: 48))
    }

    func testShowsToTheRightOfTheMenuLevelWithThePointer() {
        let menu = NSRect(x: 100, y: 300, width: 250, height: 400)
        let frame = ClipPreview.frame(size: size, besideMenu: menu, pointerY: 500, visibleFrame: visible)
        XCTAssertEqual(frame, NSRect(x: 356, y: 425, width: 200, height: 150))
    }

    func testShowsToTheLeftWhenThereIsNoRoomOnTheRight() {
        let menu = NSRect(x: 1200, y: 300, width: 230, height: 400)
        let frame = ClipPreview.frame(size: size, besideMenu: menu, pointerY: 500, visibleFrame: visible)
        XCTAssertEqual(frame.maxX, 1194)
    }

    func testStaysOnScreenNearTheBottom() {
        let menu = NSRect(x: 100, y: 60, width: 250, height: 300)
        let frame = ClipPreview.frame(size: size, besideMenu: menu, pointerY: 65, visibleFrame: visible)
        XCTAssertEqual(frame.minY, 60)
    }
}

@MainActor
final class ClipPreviewDelayTests: XCTestCase {
    func testDefaultDelayIsTwoSeconds() {
        let defaults = UserDefaults(suiteName: "ClipPreviewDelayTests")!
        defaults.removePersistentDomain(forName: "ClipPreviewDelayTests")
        Settings.registerDefaults(defaults)
        XCTAssertEqual(defaults.double(forKey: Settings.Key.previewDelay), 2)
    }
}

@MainActor
final class PreviewContentTests: XCTestCase {
    func testTextClipsPreviewTheirTextWithClickHints() {
        let content = MenuController.previewContent(for: Clip(text: "hello there", created: Date()))
        XCTAssertEqual(content.text, "hello there")
        XCTAssertNil(content.image)
        XCTAssertTrue(content.caption.contains("⌥-click"))
        XCTAssertFalse(content.caption.contains("another device"))
    }

    func testLongTextIsCutTo500Characters() {
        let content = MenuController.previewContent(for: Clip(text: String(repeating: "x", count: 2000), created: Date()))
        XCTAssertEqual(content.text?.count, 500)
    }

    func testClipsFromAnotherMacSaySo() {
        var clip = Clip(text: "from the laptop", created: Date())
        clip.fromOtherDevice = true
        XCTAssertTrue(MenuController.previewContent(for: clip).caption.contains("another device"))
    }

    func testImageClipsPreviewThePictureAndItsSize() throws {
        let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let content = MenuController.previewContent(for: Clip(image: png, created: Date()))
        XCTAssertNotNil(content.image)
        XCTAssertNil(content.text)
        XCTAssertTrue(content.caption.hasPrefix("\(rep.pixelsWide) × \(rep.pixelsHigh) pixels"), content.caption)
    }
}

@MainActor
final class PreviewTextSizeTests: XCTestCase {
    func testLongTextWrapsOntoManyLines() {
        let label = NSTextField(wrappingLabelWithString: String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 12))
        label.font = .menuFont(ofSize: 0)
        label.maximumNumberOfLines = 20
        label.cell?.truncatesLastVisibleLine = true
        let size = ClipPreview.textSize(of: label)
        XCTAssertGreaterThan(size.height, 100, "should wrap, not squeeze onto one line")
        XCTAssertLessThanOrEqual(size.width, ClipPreview.maxSize.width + 8)
    }
}
