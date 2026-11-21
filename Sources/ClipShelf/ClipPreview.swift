import AppKit

/// A preview of a clip, shown beside the menu once its row has stayed
/// highlighted (by the mouse or the arrow keys) for the delay set in
/// Settings: the picture for an image, the text for everything else, and
/// what a modifier-click does. It replaces menu tooltips, whose timing macOS
/// controls, so every row waits the same delay.
@MainActor
final class ClipPreview: NSObject, NSMenuDelegate {
    struct Content {
        var image: NSImage?
        var text: String?
        /// Small print under the preview (image size, where it was copied, click hints).
        var caption: String
    }

    /// Largest preview, in points. Smaller images are shown at their own size.
    static let maxSize = NSSize(width: 360, height: 360)
    private static let padding: CGFloat = 8
    private static let spacing: CGFloat = 6

    /// What to preview for a clip ID, or nil for rows that aren't clips.
    private let contentForClip: (UUID) -> Content?
    /// Seconds a row stays highlighted before its preview appears; negative means never.
    private let delay: () -> TimeInterval
    private var shownID: UUID?
    private var pendingID: UUID?
    private var timer: Timer?

    init(delay: @escaping () -> TimeInterval = { Settings.previewDelay },
         contentForClip: @escaping (UUID) -> Content?) {
        self.delay = delay
        self.contentForClip = contentForClip
    }

    private lazy var imageView: NSImageView = {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        view.layer?.masksToBounds = true
        return view
    }()

    private lazy var textLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 20
        // Wrap, and end the last line with "…" when the text runs past it.
        // (Setting lineBreakMode to .byTruncatingTail would stop wrapping and
        // squeeze the text onto one line.)
        label.cell?.truncatesLastVisibleLine = true
        label.preferredMaxLayoutWidth = Self.maxSize.width
        return label
    }()

    private lazy var caption: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = Self.maxSize.width
        return label
    }()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        // Above the open menus, never taking clicks or focus from them.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.addSubview(imageView)
        background.addSubview(textLabel)
        background.addSubview(caption)
        panel.contentView = background
        return panel
    }()

    // MARK: NSMenuDelegate (folder submenus use this object as their delegate)

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        update(for: item)
    }

    func menuDidClose(_ menu: NSMenu) {
        hide()
    }

    // MARK: Showing

    /// Waits for the row to stay highlighted for the delay set in Settings.
    /// Every row waits the full delay; moving to another row hides the
    /// preview and starts the wait again.
    func update(for item: NSMenuItem?) {
        guard let id = item?.representedObject as? UUID else { return hide() }
        if id == pendingID { return }  // already waiting for, or showing, this row
        let wait = delay()
        guard wait >= 0, let content = contentForClip(id) else { return hide() }
        hide()
        pendingID = id
        if wait == 0 {
            show(content, id: id)
            return
        }
        // .common includes the menu's event-tracking mode, so the timer fires while the menu is open.
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pendingID == id else { return }
                self.timer = nil
                self.show(content, id: id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        cancelTimer()
        pendingID = nil
        shownID = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func show(_ content: Content, id: UUID) {
        shownID = id
        let pad = Self.padding

        // The main part: the picture, scaled down to fit, or the text, wrapped.
        var body = NSSize.zero
        imageView.isHidden = content.image == nil
        textLabel.isHidden = content.image != nil || content.text == nil
        if let image = content.image {
            body = Self.fittedSize(Self.pixelSize(of: image), within: Self.maxSize)
            imageView.image = image
        } else if let text = content.text {
            textLabel.stringValue = text
            body = Self.textSize(of: textLabel)
        }

        caption.stringValue = content.caption
        caption.preferredMaxLayoutWidth = max(body.width, 220)
        let captionSize = caption.fittingSize

        let width = max(body.width, captionSize.width, 120)
        let gap = body.height > 0 && !content.caption.isEmpty ? Self.spacing : 0
        let size = NSSize(width: width + pad * 2, height: body.height + gap + captionSize.height + pad * 2)

        caption.frame = NSRect(x: pad, y: pad, width: width, height: captionSize.height)
        let bodyFrame = NSRect(x: content.image != nil ? (size.width - body.width) / 2 : pad,
                               y: pad + captionSize.height + gap, width: body.width, height: body.height)
        imageView.frame = bodyFrame
        textLabel.frame = bodyFrame

        panel.setFrame(placement(for: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Beside the open menu that holds the row (to the right, or to the left
    /// when there's no room), level with the pointer, kept on screen.
    private func placement(for size: NSSize) -> NSRect {
        let pointer = NSEvent.mouseLocation
        let menus = Self.openMenuFrames(excluding: panel.windowNumber)
        // The menu under the pointer, else the frontmost one (a submenu
        // opened with the arrow keys).
        let menuFrame = menus.first { NSMouseInRect(pointer, $0, false) } ?? menus.first
            ?? NSRect(x: pointer.x, y: pointer.y, width: 0, height: 0)
        let screen = NSScreen.screens.first { $0.frame.intersects(menuFrame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? menuFrame.insetBy(dx: -2000, dy: -2000)
        return Self.frame(size: size, besideMenu: menuFrame, pointerY: pointer.y, visibleFrame: visible)
    }

    /// Frames of this app's open menus, front to back, in screen
    /// coordinates. AppKit's window list doesn't include menu windows, but
    /// the window server's does (reading your own windows' bounds needs no
    /// permission).
    private static func openMenuFrames(excluding panelNumber: Int) -> [NSRect] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let pid = ProcessInfo.processInfo.processIdentifier
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return info.compactMap { window -> NSRect? in
            guard (window[kCGWindowOwnerPID as String] as? Int).map(Int32.init) == pid,
                  (window[kCGWindowNumber as String] as? Int) != panelNumber,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= menuLevel,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 20, bounds.height > 20 else { return nil }
            // Window-server coordinates start at the top left of the main screen.
            return NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        }
    }

    // MARK: Geometry (pure, tested)

    /// The size a wrapping label needs for its text, at most `maxSize` wide.
    static func textSize(of label: NSTextField) -> NSSize {
        label.preferredMaxLayoutWidth = maxSize.width
        let size = label.fittingSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    static func pixelSize(of image: NSImage) -> NSSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    /// Scales down to fit `bounds`, keeping the aspect ratio. Never scales up.
    static func fittedSize(_ size: NSSize, within bounds: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 1, height: 1) }
        let scale = min(1, bounds.width / size.width, bounds.height / size.height)
        return NSSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    static func frame(size: NSSize, besideMenu menu: NSRect, pointerY: CGFloat, visibleFrame: NSRect) -> NSRect {
        let gap: CGFloat = 6
        var x = menu.maxX + gap
        if x + size.width > visibleFrame.maxX { x = menu.minX - gap - size.width }
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width)

        // Centered on the pointer when it's over the menu, else at the menu's top.
        let centerY = (menu.minY...menu.maxY).contains(pointerY) ? pointerY : menu.maxY - size.height / 2
        var y = centerY - size.height / 2
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
