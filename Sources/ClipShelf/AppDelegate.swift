import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipStore!
    private var menuController: MenuController!
    private var settingsWindow: NSWindow?

    private enum HotKeyID {
        static let history: UInt32 = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()

        store = ClipStore()
        store.startWatching()

        menuController = MenuController(store: store)
        menuController.openSettings = { [weak self] in self?.showSettings() }
        menuController.importClipMenuHistory = { [weak self] in self?.importClipMenuHistory() }

        let hotKey = Settings.historyHotKey
        HotKeyCenter.shared.register(
            id: HotKeyID.history,
            keyCode: hotKey.keyCode,
            modifiers: hotKey.modifiers
        ) { [weak self] in
            MainActor.assumeIsolated { self?.menuController.popUpHistoryMenu() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveNow()
    }

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(onLimitChange: { [weak self] in self?.store.applyLimit() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "ClipShelf Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func importClipMenuHistory() {
        NSApp.activate()
        let alert = NSAlert()
        do {
            let clips = try ClipMenuImporter.importClips()
            let added = store.merge(clips)
            alert.messageText = "Imported ClipMenu history"
            alert.informativeText = "Added \(added) of \(clips.count) items. Items already in ClipShelf were skipped."
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't import ClipMenu history"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }
}
