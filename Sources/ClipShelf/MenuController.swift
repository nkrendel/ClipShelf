import AppKit

/// Builds the history menu for the menu-bar icon and the global hotkey.
///
/// Clicking an item copies it and (optionally) pastes it into the app you
/// were using. Modifier keys change what a click does:
/// ⌥ pastes as plain text, ⇧ only copies, ⌃ removes the item.
///
/// The search field at the top has focus while the menu is open, so typing
/// searches the whole history: the menu switches to a flat list of matches,
/// each showing its history number and the folder it lives in, with the
/// first match selected so Return pastes it.
@MainActor
final class MenuController: NSObject, NSMenuDelegate, NSSearchFieldDelegate {
    /// Most matches listed at once; more are summarized in one line.
    static let maxSearchResults = 50

    private let store: ClipStore
    private let statusItem: NSStatusItem
    private var previousApp: NSRunningApplication?
    private var selectedDuringPopUp = false

    // Search state, alive only while a history menu is open.
    private var query = ""
    private var openMenu: NSMenu?
    private var firstResultItem: NSMenuItem?
    private var pendingSelection: NSMenuItem?
    /// Set when Escape closed the menu during a search: it reopens with the search cleared.
    private var reopenRequested = false
    private lazy var searchField: NSSearchField = {
        let field = NSSearchField(frame: NSRect(x: 14, y: 4, width: 252, height: 24))
        field.placeholderString = "Type to search history"
        field.autoresizingMask = [.width]
        field.delegate = self
        field.target = self
        field.action = #selector(searchFieldChanged(_:))
        field.sendsSearchStringImmediately = true
        return field
    }()
    private lazy var searchItem: NSMenuItem = {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        view.autoresizingMask = [.width]
        view.addSubview(searchField)
        let item = NSMenuItem()
        item.view = view
        return item
    }()

    var openSettings: () -> Void = {}
    var importClipMenuHistory: () -> Void = {}

    init(store: ClipStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipShelf")
                ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipShelf")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: Showing the menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    /// Shows the history menu at the mouse pointer (hotkey).
    func popUpHistoryMenu() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        selectedDuringPopUp = false

        // The menu needs keyboard focus for typing and arrow keys.
        NSApp.activate()
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        repeat {
            reopenRequested = false
            let menu = NSMenu()
            menu.delegate = self
            rebuild(menu)
            let origin = screen.map {
                MenuLayout.popUpOrigin(pointer: pointer, menuSize: menu.size, visibleFrame: $0.visibleFrame)
            } ?? pointer
            menu.popUp(positioning: nil, at: origin, in: nil)
        } while reopenRequested && !selectedDuringPopUp

        if !selectedDuringPopUp {
            previousApp?.activate()
            previousApp = nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenu = menu
        guard menu.items.first === searchItem else { return }
        // The field's window only exists once the menu is on screen, so focus
        // it on the next pass of the menu's event-tracking run loop.
        perform(#selector(focusSearchField), with: nil, afterDelay: 0, inModes: [.eventTracking, .common])
    }

    @objc private func focusSearchField() {
        guard openMenu != nil, let window = searchField.window else { return }
        window.makeFirstResponder(searchField)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === openMenu else { return }
        openMenu = nil

        // The menu handles Escape itself and closes; neither the search field
        // nor NSEvent monitors see it. So when Escape closes the menu during a
        // search, open it again with the search cleared, as if Escape had only
        // cleared it.
        let event = NSApp.currentEvent
        if !query.isEmpty, pendingSelection == nil, event?.type == .keyDown, event?.keyCode == 53 {
            reopenRequested = true
            if menu === statusItem.menu {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.reopenRequested else { return }
                    self.reopenRequested = false
                    self.statusItem.button?.performClick(nil)
                }
            }
        }
        // Take the field out of the closed menu: the next menu may be a different one.
        searchItem.menu?.removeItem(searchItem)
        query = ""
        searchField.stringValue = ""
        firstResultItem = nil
        if let item = pendingSelection {
            pendingSelection = nil
            selectClip(item)
        }
    }

    private func rebuild(_ menu: NSMenu) {
        firstResultItem = nil
        let clips = store.history.clips

        if clips.isEmpty {
            menu.removeAllItems()
            let empty = NSMenuItem(title: "No clipboard history yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else if menu.items.first === searchItem {
            // Keep the search field in place so it keeps keyboard focus while you type.
            while menu.items.count > 1 { menu.removeItem(at: 1) }
        } else {
            menu.removeAllItems()
            searchField.stringValue = query
            menu.addItem(searchItem)
        }

        if query.isEmpty {
            addHistoryItems(to: menu, clips: clips)
        } else {
            addSearchResults(to: menu, clips: clips)
        }
        addCommands(to: menu, hasClips: !clips.isEmpty)
    }

    private func addHistoryItems(to menu: NSMenu, clips: [Clip]) {
        let inline = min(Settings.inlineCount, clips.count)
        for index in 0..<inline {
            let key = index < 10 ? String((index + 1) % 10) : ""
            menu.addItem(makeItem(for: clips[index], number: index + 1, keyEquivalent: key))
        }

        var start = inline
        while start < clips.count {
            let end = min(start + Settings.folderSize, clips.count)
            let folder = NSMenuItem(title: "\(start + 1) – \(end)", action: nil, keyEquivalent: "")
            folder.image = symbol("folder")
            let submenu = NSMenu()
            for index in start..<end {
                submenu.addItem(makeItem(for: clips[index], number: index + 1, keyEquivalent: ""))
            }
            folder.submenu = submenu
            menu.addItem(folder)
            start = end
        }
    }

    private func addSearchResults(to menu: NSMenu, clips: [Clip]) {
        let results = ClipSearch.search(clips, query: query, excerptLength: max(Settings.titleLength, 50))
        if results.isEmpty {
            let none = NSMenuItem(title: "No matches", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }

        let font = NSFont.menuFont(ofSize: 0)
        let bold = NSFont.boldSystemFont(ofSize: font.pointSize)
        for result in results.prefix(Self.maxSearchResults) {
            let clip = clips[result.index]
            let item = makeItem(for: clip, number: result.index + 1, keyEquivalent: "")

            // "37. …excerpt with matches in bold…  in 31 – 40"
            let prefix = "\(result.index + 1). "
            let title = NSMutableAttributedString(string: prefix + result.excerpt, attributes: [.font: font])
            let offset = (prefix as NSString).length
            for range in result.highlights {
                title.addAttribute(.font, value: bold, range: NSRange(location: range.location + offset, length: range.length))
            }
            let folder = MenuLayout.folder(
                containing: result.index, inlineCount: Settings.inlineCount,
                folderSize: Settings.folderSize, total: clips.count)
            if let folder {
                title.append(NSAttributedString(string: "   in \(folder.lowerBound) – \(folder.upperBound)", attributes: [
                    .font: NSFont.menuFont(ofSize: font.pointSize - 2),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            }
            item.attributedTitle = title
            menu.addItem(item)
            if firstResultItem == nil { firstResultItem = item }
        }

        if results.count > Self.maxSearchResults {
            let more = NSMenuItem(
                title: "\(results.count - Self.maxSearchResults) more matches. Keep typing to narrow them down.",
                action: nil, keyEquivalent: "")
            more.isEnabled = false
            menu.addItem(more)
        }
    }

    private func addCommands(to menu: NSMenu, hasClips: Bool) {
        menu.addItem(.separator())

        if hasClips {
            menu.addItem(makeCommand("Clear History…", action: #selector(clearHistory)))
        }
        if FileManager.default.fileExists(atPath: ClipMenuImporter.defaultFileURL.path) {
            menu.addItem(makeCommand("Import ClipMenu History", action: #selector(importHistory)))
        }
        if Settings.pasteAfterSelect && !Paster.isTrusted {
            menu.addItem(makeCommand("Allow Automatic Pasting…", action: #selector(requestAccessibility)))
        }
        let settings = makeCommand("Settings…", action: #selector(showSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(makeCommand("Quit ClipShelf", action: #selector(quit)))
    }

    private func makeItem(for clip: Clip, number: Int, keyEquivalent: String) -> NSMenuItem {
        var title = clip.menuTitle(maxLength: Settings.titleLength)
        if title.isEmpty { title = "(empty)" }
        if Settings.numberItems { title = "\(number). \(title)" }

        let item = NSMenuItem(title: title, action: #selector(selectClip(_:)), keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = []
        item.target = self
        item.representedObject = clip.id
        item.image = icon(for: clip)

        var tip = String((clip.text ?? clip.url?.absoluteString ?? clip.menuTitle(maxLength: 500)).prefix(500))
        if clip.fromOtherDevice { tip += "\n\nCopied on another device (Universal Clipboard)" }
        tip += "\n\n⌥-click: paste as plain text · ⇧-click: copy only · ⌃-click: remove"
        item.toolTip = tip
        return item
    }

    private func makeCommand(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func icon(for clip: Clip) -> NSImage? {
        if clip.fromOtherDevice && Settings.markOtherDeviceClips {
            return symbol("laptopcomputer.and.arrow.down") ?? symbol("icloud.and.arrow.down")
        }
        switch clip.kind {
        case .image:
            if let data = clip.image, let image = NSImage(data: data) {
                image.size = NSSize(width: 16, height: 16)
                return image
            }
            return symbol("photo")
        case .files: return symbol("doc")
        case .url: return symbol("link")
        case .pdf: return symbol("doc.richtext")
        case .richText: return symbol("textformat")
        case .text: return symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: Search

    /// Typing goes straight into the search field, which has focus while the
    /// menu is open. Arrow keys and Return would stay in the field, so they
    /// are handled here to keep the menu usable from the keyboard. (Escape
    /// never gets here; see `menuDidClose`.)
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let menu = openMenu else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveHighlight(by: 1, in: menu)
        case #selector(NSResponder.moveUp(_:)):
            moveHighlight(by: -1, in: menu)
        case #selector(NSResponder.insertNewline(_:)):
            // Return pastes the selected item, or the first one.
            let highlighted = menu.highlightedItem.flatMap { $0.representedObject is UUID ? $0 : nil }
            guard let item = highlighted ?? clipItems(in: menu).first else { return true }
            pendingSelection = item
            menu.cancelTracking()
        default:
            return false
        }
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        let text = searchField.stringValue
        // Before a search starts, 1–0 pick the numbered items, as in ClipMenu.
        if query.isEmpty, text.count == 1, let digit = text.first?.wholeNumberValue, let menu = openMenu {
            let index = digit == 0 ? 9 : digit - 1
            let items = clipItems(in: menu)
            if index < min(Settings.inlineCount, items.count) {
                searchField.stringValue = ""
                pendingSelection = items[index]
                menu.cancelTracking()
                return
            }
        }
        setQuery(text)
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        // Typing is handled by controlTextDidChange; this catches the clear button.
        if sender.stringValue != query { setQuery(sender.stringValue) }
    }

    private func setQuery(_ newQuery: String) {
        query = newQuery
        guard let menu = openMenu else { return }
        rebuild(menu)
        if let first = firstResultItem { highlight(first, in: menu) }
    }

    /// The history or search-result items in the menu, top to bottom.
    private func clipItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { $0.representedObject is UUID }
    }

    private func moveHighlight(by step: Int, in menu: NSMenu) {
        let items = clipItems(in: menu)
        guard !items.isEmpty else { return }
        let current = menu.highlightedItem.flatMap { items.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), items.count - 1) } ?? (step > 0 ? 0 : items.count - 1)
        highlight(items[next], in: menu)
    }

    /// Selects an item in an open menu. AppKit has no public API for this;
    /// NSMenu responds to `highlightItem:`, and if it ever stops, Return
    /// still pastes the first item.
    private func highlight(_ item: NSMenuItem, in menu: NSMenu) {
        let selector = NSSelectorFromString("highlightItem:")
        if menu.responds(to: selector) {
            menu.perform(selector, with: item)
        }
    }

    // MARK: Actions

    @objc private func selectClip(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        selectedDuringPopUp = true
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        let target = previousApp
        previousApp = nil

        if flags.contains(.control) {
            store.remove(id)
            target?.activate()
            return
        }

        store.copyToPasteboard(id, plainText: flags.contains(.option))
        target?.activate()

        guard Settings.pasteAfterSelect, !flags.contains(.shift) else { return }
        guard Paster.isTrusted else {
            Paster.requestTrust()
            return
        }
        // Give the target app a moment to become active before sending ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Paster.sendPasteKeystroke()
        }
    }

    @objc private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear your clipboard history?"
        alert.informativeText = "This removes all \(store.history.clips.count) items. It can't be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }

    @objc private func importHistory() {
        importClipMenuHistory()
    }

    @objc private func requestAccessibility() {
        Paster.requestTrust()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

