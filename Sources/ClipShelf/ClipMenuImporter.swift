import AppKit

/// Imports history from ClipMenu's clips.data, an NSKeyedArchiver archive
/// whose root is an array of ClipMenu `Clip` objects with the keys
/// stringValue, RTF, RTFD, PDF, filenames, URL, image, types,
/// createdDate and lastUsedDate.
enum ClipMenuImporter {
    static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ClipMenu/clips.data")
    }

    enum ImportError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let reason): return "Could not read ClipMenu history: \(reason)"
            }
        }
    }

    static func importClips(from url: URL = defaultFileURL) throws -> [Clip] {
        let data = try Data(contentsOf: url)
        return try clips(fromArchive: data)
    }

    static func clips(fromArchive data: Data) throws -> [Clip] {
        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        // The archive is local, user-owned data written by ClipMenu; its
        // classes predate secure coding, so it is read without it.
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(LegacyClip.self, forClassName: "Clip")
        defer { unarchiver.finishDecoding() }

        guard let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [Any] else {
            throw ImportError.unreadable("unexpected archive layout")
        }
        return root.compactMap { ($0 as? LegacyClip)?.clip }
    }
}

/// Decodes one ClipMenu `Clip`. Only used for importing.
@objc(ClipShelfLegacyClip)
final class LegacyClip: NSObject, NSCoding {
    let clip: Clip?

    init?(coder: NSCoder) {
        let text = coder.decodeObject(forKey: "stringValue") as? String
        let rtf = coder.decodeObject(forKey: "RTF") as? Data
        let rtfd = coder.decodeObject(forKey: "RTFD") as? Data
        let pdf = coder.decodeObject(forKey: "PDF") as? Data

        let filenames = coder.decodeObject(forKey: "filenames") as? [String]
        let fileURLs = filenames?.map { URL(fileURLWithPath: $0) }

        var url: URL?
        switch coder.decodeObject(forKey: "URL") {
        case let value as URL: url = value
        case let value as String: url = URL(string: value)
        case let values as [String]: url = values.first.flatMap(URL.init(string:))
        default: break
        }
        if url?.isFileURL == true { url = nil }

        var image: Data?
        if let nsImage = coder.decodeObject(forKey: "image") as? NSImage,
           let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            image = rep.representation(using: .png, properties: [:])
        }

        let created = coder.decodeObject(forKey: "createdDate") as? Date ?? Date()
        let lastUsed = coder.decodeObject(forKey: "lastUsedDate") as? Date ?? created

        let clip = Clip(
            text: text, rtf: rtf, rtfd: rtfd, pdf: pdf,
            fileURLs: fileURLs, url: url, image: image,
            created: created, lastUsed: lastUsed
        )
        self.clip = clip.isEmpty ? nil : clip
        super.init()
    }

    func encode(with coder: NSCoder) {
        // Import only.
    }
}
