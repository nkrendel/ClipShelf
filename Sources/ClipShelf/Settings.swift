import Carbon.HIToolbox
import Foundation

/// Which pasteboard representations to keep, like ClipMenu's
/// "Select clipboard types to store".
struct StoreTypes: Equatable {
    var text = true
    var richText = true
    var files = true
    var urls = true
    var images = true
    var pdf = true
}

/// User preferences, stored in UserDefaults.
enum Settings {
    enum Key {
        static let maxHistory = "maxHistory"
        static let pasteAfterSelect = "pasteAfterSelect"
        static let inlineCount = "inlineCount"
        static let folderSize = "folderSize"
        static let titleLength = "titleLength"
        static let numberItems = "numberItems"
        static let markOtherDeviceClips = "markOtherDeviceClips"
        static let previewDelay = "previewDelay"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let storeText = "storeText"
        static let storeRichText = "storeRichText"
        static let storeFiles = "storeFiles"
        static let storeURLs = "storeURLs"
        static let storeImages = "storeImages"
        static let storePDF = "storePDF"
        static let historyHotKeyCode = "historyHotKeyCode"
        static let historyHotKeyModifiers = "historyHotKeyModifiers"
    }

    /// Password managers are skipped by default. Apps that mark copies as
    /// concealed (org.nspasteboard.ConcealedType) are skipped regardless.
    static let defaultExcludedBundleIDs = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.maxHistory: 100,
            Key.pasteAfterSelect: true,
            // Like ClipMenu: every clip in a folder (1–10, 11–20, …).
            Key.inlineCount: 0,
            Key.folderSize: 10,
            Key.titleLength: 40,
            Key.numberItems: true,
            Key.markOtherDeviceClips: true,
            Key.previewDelay: 2.0,
            Key.excludedBundleIDs: defaultExcludedBundleIDs,
            Key.storeText: true,
            Key.storeRichText: true,
            Key.storeFiles: true,
            Key.storeURLs: true,
            Key.storeImages: true,
            Key.storePDF: true,
            // ⌃⌘V, the shortcut used in the existing ClipMenu setup.
            Key.historyHotKeyCode: kVK_ANSI_V,
            Key.historyHotKeyModifiers: cmdKey | controlKey,
        ])
    }

    static var defaults: UserDefaults { .standard }

    static var maxHistory: Int { max(1, defaults.integer(forKey: Key.maxHistory)) }
    static var pasteAfterSelect: Bool { defaults.bool(forKey: Key.pasteAfterSelect) }
    static var inlineCount: Int { max(0, defaults.integer(forKey: Key.inlineCount)) }
    static var folderSize: Int { max(1, defaults.integer(forKey: Key.folderSize)) }
    static var titleLength: Int { max(10, defaults.integer(forKey: Key.titleLength)) }
    static var numberItems: Bool { defaults.bool(forKey: Key.numberItems) }
    static var markOtherDeviceClips: Bool { defaults.bool(forKey: Key.markOtherDeviceClips) }
    /// Seconds a row stays highlighted before its preview appears;
    /// negative turns previews off.
    static var previewDelay: TimeInterval { defaults.double(forKey: Key.previewDelay) }
    static var excludedBundleIDs: Set<String> {
        Set(defaults.stringArray(forKey: Key.excludedBundleIDs) ?? [])
    }

    static var storeTypes: StoreTypes {
        StoreTypes(
            text: defaults.bool(forKey: Key.storeText),
            richText: defaults.bool(forKey: Key.storeRichText),
            files: defaults.bool(forKey: Key.storeFiles),
            urls: defaults.bool(forKey: Key.storeURLs),
            images: defaults.bool(forKey: Key.storeImages),
            pdf: defaults.bool(forKey: Key.storePDF)
        )
    }

    static var historyHotKey: (keyCode: UInt32, modifiers: UInt32) {
        (UInt32(defaults.integer(forKey: Key.historyHotKeyCode)),
         UInt32(defaults.integer(forKey: Key.historyHotKeyModifiers)))
    }
}
