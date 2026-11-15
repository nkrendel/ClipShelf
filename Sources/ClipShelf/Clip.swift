import CryptoKit
import Foundation

/// One clipboard entry. Mirrors the representations ClipMenu stored
/// (plain text, RTF, RTFD, PDF, file names, URL, image) so a clip can be
/// put back on the pasteboard with its formatting intact.
struct Clip: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text, richText, files, url, image, pdf
    }

    var id = UUID()
    var text: String?
    var rtf: Data?
    var rtfd: Data?
    var pdf: Data?
    var fileURLs: [URL]?
    var url: URL?
    /// PNG-encoded image data.
    var image: Data?
    var created: Date
    var lastUsed: Date
    /// True when macOS Universal Clipboard delivered this clip from another device.
    var fromOtherDevice = false
    var contentHash: String

    init(
        text: String? = nil,
        rtf: Data? = nil,
        rtfd: Data? = nil,
        pdf: Data? = nil,
        fileURLs: [URL]? = nil,
        url: URL? = nil,
        image: Data? = nil,
        created: Date,
        lastUsed: Date? = nil,
        fromOtherDevice: Bool = false
    ) {
        self.text = text
        self.rtf = rtf
        self.rtfd = rtfd
        self.pdf = pdf
        self.fileURLs = fileURLs.flatMap { $0.isEmpty ? nil : $0 }
        self.url = url
        self.image = image
        self.created = created
        self.lastUsed = lastUsed ?? created
        self.fromOtherDevice = fromOtherDevice
        self.contentHash = Clip.hash(text: text, fileURLs: self.fileURLs, url: url, image: image, pdf: pdf)
    }

    var isEmpty: Bool {
        text == nil && rtf == nil && rtfd == nil && pdf == nil && fileURLs == nil && url == nil && image == nil
    }

    var kind: Kind {
        if let fileURLs, !fileURLs.isEmpty { return .files }
        if image != nil, text == nil { return .image }
        if pdf != nil, text == nil { return .pdf }
        if rtf != nil || rtfd != nil { return .richText }
        if url != nil, text == nil || text == url?.absoluteString { return .url }
        return .text
    }

    /// Identity used to detect a re-copy of the same content. Rich-text
    /// variants of the same visible text count as the same clip, as in ClipMenu.
    static func hash(text: String?, fileURLs: [URL]?, url: URL?, image: Data?, pdf: Data?) -> String {
        var hasher = SHA256()
        func add(_ tag: String, _ data: Data?) {
            guard let data else { return }
            hasher.update(data: Data(tag.utf8))
            hasher.update(data: data)
        }
        add("t", text.map { Data($0.utf8) })
        add("f", fileURLs.map { Data($0.map(\.path).joined(separator: "\n").utf8) })
        add("u", url.map { Data($0.absoluteString.utf8) })
        if text == nil {
            add("i", image)
            add("p", pdf)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The single-line label shown in the menu.
    func menuTitle(maxLength: Int) -> String {
        let raw: String
        switch kind {
        case .files:
            raw = (fileURLs ?? []).map(\.lastPathComponent).joined(separator: ", ")
        case .image:
            raw = "(Image)"
        case .pdf:
            raw = "(PDF)"
        case .url:
            raw = url?.absoluteString ?? ""
        case .text, .richText:
            raw = text ?? ""
        }
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard maxLength > 0, collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)) + "…"
    }
}

/// Ordered clipboard history, most recently used first.
struct ClipHistory: Codable, Equatable {
    private(set) var clips: [Clip] = []

    /// Adds a clip, or moves an identical existing clip to the top.
    /// Returns true when the history changed.
    @discardableResult
    mutating func add(_ clip: Clip, limit: Int, now: Date = Date()) -> Bool {
        guard !clip.isEmpty else { return false }
        if let index = clips.firstIndex(where: { $0.contentHash == clip.contentHash }) {
            var existing = clips.remove(at: index)
            existing.lastUsed = now
            clips.insert(existing, at: 0)
        } else {
            clips.insert(clip, at: 0)
        }
        trim(to: limit)
        return true
    }

    mutating func touch(id: Clip.ID, now: Date = Date()) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = clips.remove(at: index)
        clip.lastUsed = now
        clips.insert(clip, at: 0)
    }

    mutating func remove(id: Clip.ID) {
        clips.removeAll { $0.id == id }
    }

    mutating func clear() {
        clips.removeAll()
    }

    mutating func trim(to limit: Int) {
        if limit >= 0, clips.count > limit {
            clips.removeLast(clips.count - limit)
        }
    }

    func clip(id: Clip.ID) -> Clip? {
        clips.first { $0.id == id }
    }

    /// Merges imported clips under the existing ones, skipping duplicates.
    mutating func merge(_ imported: [Clip], limit: Int) -> Int {
        var known = Set(clips.map(\.contentHash))
        var added = 0
        for clip in imported.sorted(by: { $0.lastUsed > $1.lastUsed }) where !known.contains(clip.contentHash) {
            clips.append(clip)
            known.insert(clip.contentHash)
            added += 1
        }
        clips.sort { $0.lastUsed > $1.lastUsed }
        trim(to: limit)
        return added
    }
}
