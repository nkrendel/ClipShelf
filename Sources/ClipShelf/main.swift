import AppKit

// `ClipShelf --check-clipmenu-import` reports how many ClipMenu clips can be
// imported (counts only, no clip contents) and exits.
if CommandLine.arguments.contains("--check-clipmenu-import") {
    do {
        let clips = try ClipMenuImporter.importClips()
        var kinds: [String: Int] = [:]
        for clip in clips { kinds[clip.kind.rawValue, default: 0] += 1 }
        print("Readable ClipMenu clips: \(clips.count)")
        for (kind, count) in kinds.sorted(by: { $0.key < $1.key }) { print("  \(kind): \(count)") }
        exit(0)
    } catch {
        print(error.localizedDescription)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// Menu-bar only: no Dock icon, like ClipMenu's LSUIElement.
app.setActivationPolicy(.accessory)
app.run()
