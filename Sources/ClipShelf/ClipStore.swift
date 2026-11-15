import AppKit

/// Watches the general pasteboard and keeps the clipboard history.
///
/// macOS has no "clipboard changed" notification, so like ClipMenu this
/// polls the pasteboard's change count. Universal Clipboard copies from
/// another Mac or iPhone arrive the same way, so they are recorded too.
@MainActor
final class ClipStore {
    static let pollInterval: TimeInterval = 0.5

    private(set) var history = ClipHistory()
    private let pasteboard: NSPasteboard
    private let fileURL: URL
    private var lastChangeCount: Int
    private var pollTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?

    init(pasteboard: NSPasteboard = .general, fileURL: URL = ClipStore.defaultFileURL) {
        self.pasteboard = pasteboard
        self.fileURL = fileURL
        self.lastChangeCount = pasteboard.changeCount
        load()
    }

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ClipShelf", isDirectory: true)
            .appendingPathComponent("history.plist")
    }

    func startWatching() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Settings.excludedBundleIDs.contains(front) {
            return
        }
        guard let clip = PasteboardIO.readClip(from: pasteboard, storing: Settings.storeTypes) else { return }
        if history.add(clip, limit: Settings.maxHistory) {
            scheduleSave()
        }
    }

    /// Copies a history item to the pasteboard and moves it to the top.
    func copyToPasteboard(_ id: Clip.ID, plainText: Bool) {
        guard let clip = history.clip(id: id) else { return }
        PasteboardIO.write(clip, to: pasteboard, plainText: plainText)
        lastChangeCount = pasteboard.changeCount
        history.touch(id: id)
        scheduleSave()
    }

    func remove(_ id: Clip.ID) {
        history.remove(id: id)
        scheduleSave()
    }

    func clear() {
        history.clear()
        saveNow()
    }

    func merge(_ clips: [Clip]) -> Int {
        let added = history.merge(clips, limit: Settings.maxHistory)
        saveNow()
        return added
    }

    func applyLimit() {
        history.trim(to: Settings.maxHistory)
        scheduleSave()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            history = try PropertyListDecoder().decode(ClipHistory.self, from: data)
        } catch {
            NSLog("ClipShelf: could not read history at %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(history).write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("ClipShelf: could not save history: %@", String(describing: error))
        }
    }
}
