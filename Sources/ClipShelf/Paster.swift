import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Sends ⌘V to the frontmost app, as ClipMenu did with
/// CGEventCreateKeyboardEvent(source, 9 /* V */, ...) and the Command flag.
/// Posting key events requires the Accessibility permission on current macOS.
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that lets the user grant Accessibility access.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    static func sendPasteKeystroke() -> Bool {
        guard isTrusted else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
