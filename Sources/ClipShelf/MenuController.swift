import AppKit

/// Builds the history menu for the menu-bar icon and the global hotkey.
///
/// Clicking an item copies it and (optionally) pastes it into the app you
/// were using. Modifier keys change what a click does:
/// ⌥ pastes as plain text, ⇧ only copies, ⌃ removes the item.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let store: ClipStore
    private let statusItem: NSStatusItem
    private var previousApp: NSRunningApplication?
    private var selectedDuringPopUp = false

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

        let menu = NSMenu()
        rebuild(menu)
        // The menu needs keyboard focus for arrow keys and number shortcuts.
        NSApp.activate()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)

        if !selectedDuringPopUp {
            previousApp?.activate()
            previousApp = nil
        }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let clips = store.history.clips

        if clips.isEmpty {
            let empty = NSMenuItem(title: "No clipboard history yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

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

        menu.addItem(.separator())

        if !clips.isEmpty {
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
