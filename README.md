# ClipShelf

A clipboard history for the macOS menu bar, built natively for Apple Silicon.
It replaces ClipMenu 0.4.3 (2009), which ships only Intel/PowerPC code and runs
under Rosetta.

## Build and run

Requires macOS 14+ and Xcode 26 (Swift 6.2).

```bash
./build-app.sh            # builds build/ClipShelf.app
./build-app.sh --install  # also copies it to /Applications
swift test                # unit tests
```

Quit ClipMenu before using ClipShelf: both use ⌃⌘V by default.

To paste automatically after you pick an item, allow ClipShelf in
**System Settings › Privacy & Security › Accessibility**. Because local builds
are ad-hoc signed, you may need to turn it off and on again there after a rebuild.

## Using it

- **⌃⌘V** or the menu-bar icon opens the history. The first 10 items are
  inline with keys 1–0; older ones are grouped in folders.
- **Start typing** while the menu is open to search the whole history, not
  just the top 10. Matches are listed with their history number and the folder
  they live in (e.g. `37. …invoice for March…   in 31 – 40`), matched words in
  bold. The first match is selected, so **Return** pastes it; ↑/↓ pick
  another. **Escape** clears the search (the menu closes and reopens, since
  macOS menus don't let the field see Escape); a second Escape closes it.
  Every word must match, in any order; case and accents are ignored. Before
  you type a letter, 1–0 still pick items.
- Click an item to paste it into the app you were using.
  **⌥-click** pastes as plain text, **⇧-click** only copies, **⌃-click** removes it.
- **Import ClipMenu History** (in the menu) brings over ClipMenu's
  `~/Library/Application Support/ClipMenu/clips.data`.
  `ClipShelf --check-clipmenu-import` reports what it can read, counts only.

## Copies from your other Macs

ClipMenu never synced anything itself; it has no network code. What you saw is
macOS **Universal Clipboard**, part of Handoff: a copy on one Mac becomes the
clipboard on your nearby Macs signed in to the same Apple Account, and any
clipboard manager that watches the clipboard records it.

ClipShelf records these too, and marks them with a laptop icon, using the
`com.apple.is-remote-clipboard` type macOS adds to them. Universal Clipboard
needs both Macs on the same Apple Account, Bluetooth and Wi-Fi on, Handoff on
(System Settings › General › AirDrop & Handoff), and the Macs near each other.

## How it maps to ClipMenu

Findings come from inspecting ClipMenu 0.4.3's bundle and decompiling its
Intel slice with REA and Ghidra.

| ClipMenu | ClipShelf |
|---|---|
| Timer polls `NSPasteboard.changeCount` (≤ 1 s) | Same, every 0.5 s |
| Duplicate copy bumps `lastUsedDate` | Same (by content hash) |
| Stores String, RTF, RTFD, PDF, filenames, URL, TIFF/PICT | Text, RTF, RTFD, PDF, files, URL, images (PNG) |
| Exclude list by bundle ID (default: OpenOffice) | Exclude list (default: password managers) + skips copies marked concealed/transient |
| Paste via `CGEventCreateKeyboardEvent(V)` + ⌘ | Same, needs Accessibility permission |
| Carbon `RegisterEventHotKey` (PTHotKey) | Same Carbon API |
| `clips.data` (NSKeyedArchiver) | `~/Library/Application Support/ClipShelf/history.plist` (binary plist, mode 600) |

## Not yet built

- Snippets (folders of saved text, XML import/export)
- Actions menu and JavaScript actions (planned on JavaScriptCore so ClipMenu's
  `.js` actions keep working)
- Changing the hotkey in Settings (it can be set with `defaults` for now)
- History export, menu icon styles, font size
