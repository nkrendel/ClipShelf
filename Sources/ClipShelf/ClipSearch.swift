import Foundation

/// Finds clips in the history by the words typed into the menu's search field.
enum ClipSearch {
    struct Result: Equatable {
        /// Position in the history (0 = most recent), so the menu can show where the clip lives.
        let index: Int
        let id: Clip.ID
        /// One line of the clip's text around the first match.
        let excerpt: String
        /// Where the search words appear in `excerpt` (UTF-16 ranges, for attributed strings).
        let highlights: [NSRange]
    }

    static let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The words of a query. A clip matches when it contains every word, in any order.
    static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The text a clip can be found by: its text, link, or file names.
    /// Images and PDFs without text have none.
    static func searchableText(of clip: Clip) -> String {
        let raw: String
        if clip.kind == .files {
            raw = (clip.fileURLs ?? []).map(\.lastPathComponent).joined(separator: ", ")
        } else {
            raw = clip.text ?? clip.url?.absoluteString ?? ""
        }
        return raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Matching clips in history order, most recent first.
    static func search(_ clips: [Clip], query: String, excerptLength: Int = 60) -> [Result] {
        let words = terms(query)
        guard !words.isEmpty else { return [] }

        var results: [Result] = []
        for (index, clip) in clips.enumerated() {
            let text = searchableText(of: clip) as NSString
            var firstMatch: NSRange?
            var matchesAll = true
            for word in words {
                let range = text.range(of: word, options: compareOptions)
                if range.location == NSNotFound {
                    matchesAll = false
                    break
                }
                if firstMatch.map({ range.location < $0.location }) ?? true { firstMatch = range }
            }
            guard matchesAll, let firstMatch else { continue }

            let excerpt = makeExcerpt(of: text, around: firstMatch, length: excerptLength)
            results.append(Result(
                index: index, id: clip.id, excerpt: excerpt,
                highlights: ranges(of: words, in: excerpt as NSString)))
        }
        return results
    }

    /// A window of `length` characters that includes the match, with "…" where text was cut.
    private static func makeExcerpt(of text: NSString, around match: NSRange, length: Int) -> String {
        let total = text.length
        guard length > 0, total > length else { return text as String }

        // Keep the start of the text when the match is already visible there;
        // otherwise show a little context before the match.
        var start = NSMaxRange(match) <= length ? 0 : max(0, match.location - 15)
        start = min(start, total - length)
        let window = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: length))

        var excerpt = text.substring(with: window)
        if window.location > 0 { excerpt = "…" + excerpt }
        if NSMaxRange(window) < total { excerpt += "…" }
        return excerpt
    }

    private static func ranges(of words: [String], in text: NSString) -> [NSRange] {
        var found: [NSRange] = []
        for word in words {
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.length > 0 {
                let range = text.range(of: word, options: compareOptions, range: searchRange)
                if range.location == NSNotFound || range.length == 0 { break }
                found.append(range)
                let next = NSMaxRange(range)
                searchRange = NSRange(location: next, length: text.length - next)
            }
        }
        return found.sorted { $0.location < $1.location }
    }
}

/// How the history menu groups clips: the first `inlineCount` at the top,
/// the rest in folders of `folderSize`.
enum MenuLayout {
    /// The 1-based numbers of the folder that holds the clip at `index`,
    /// or nil when the clip is shown at the top of the menu.
    static func folder(containing index: Int, inlineCount: Int, folderSize: Int, total: Int) -> ClosedRange<Int>? {
        guard index >= inlineCount, index < total else { return nil }
        let size = max(folderSize, 1)
        let start = inlineCount + (index - inlineCount) / size * size
        return (start + 1)...min(start + size, total)
    }
}
