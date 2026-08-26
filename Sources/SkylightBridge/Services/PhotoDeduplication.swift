import CryptoKit
import Foundation

/// Content-hash-based photo deduplication for Skylight uploads.
///
/// When a photo mapping is disconnected and reconnected (or a second Mac syncs
/// against the same frame), the bridge's local link table has no record of the
/// previously uploaded message. Without deduplication, every asset is
/// re-uploaded as a new Skylight message.
///
/// The deduplication tag is a short prefix of the SHA-256 of the converted
/// image data, embedded in the caption as `[sb:hash]`. Before uploading, the
/// bridge fetches existing messages in the destination album and parses their
/// captions for a matching tag. A match links the Apple asset to the existing
/// Skylight message instead of creating a duplicate.
enum PhotoDeduplication {
    static let tagPrefix = "[sb:"
    static let hashLength = 12

    /// Returns the dedup tag for a converted image's SHA-256 hash.
    static func tag(forRenderedHash hash: String) -> String {
        let shortened = String(hash.prefix(hashLength))
        return "\(tagPrefix)\(shortened)]"
    }

    /// Returns the short hash extracted from a dedup tag, or nil if the
    /// caption does not contain one. A user-visible name may itself embed
    /// bracketed text, so every `[sb:` occurrence is considered and the last
    /// well-formed tag (12 hex characters) wins.
    static func hash(fromCaption caption: String?) -> String? {
        guard let caption else { return nil }
        var extractedHash: String?
        var searchStart = caption.startIndex
        while let range = caption.range(of: tagPrefix, range: searchStart..<caption.endIndex) {
            defer { searchStart = range.upperBound }
            let afterPrefix = caption[range.upperBound...]
            guard let closeBracket = afterPrefix.firstIndex(of: "]") else { continue }
            let candidate = String(afterPrefix[..<closeBracket])
            guard candidate.count == hashLength, candidate.allSatisfy(\.isHexDigit) else {
                continue
            }
            extractedHash = candidate
        }
        return extractedHash
    }

    /// Builds the caption sent to Skylight: the user-visible name (if any)
    /// followed by the invisible dedup tag.
    static func caption(withUserCaption userCaption: String?, renderedHash: String) -> String? {
        let tag = tag(forRenderedHash: renderedHash)
        guard let userCaption, !userCaption.isEmpty else {
            return tag
        }
        return "\(userCaption) \(tag)"
    }

    /// Describes the Apple asset revision and the render settings that produce
    /// a converted image. Two runs that agree on this string cannot produce
    /// different JPEG bytes, so a sync can trust its stored hash and skip the
    /// render and encode entirely. Photos bumps `modificationDate` on any edit
    /// and `adjustmentDate` on an edit to the rendered appearance, and pixel
    /// dimensions catch a replaced original.
    ///
    /// Pass `backgroundColor` once a call site can vary it; omitting it (the
    /// default) keeps fingerprints written before that field existed valid, so
    /// existing libraries do not re-render.
    static func sourceFingerprint(
        for asset: ApplePhotoAssetSnapshot,
        maximumLongEdge: Int,
        jpegQuality: Double,
        backgroundColor: AppleRGBColor? = nil
    ) -> String {
        var fields: [String] = [
            asset.id,
            asset.modificationDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "-",
            asset.adjustmentDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "-",
            String(asset.pixelWidth),
            String(asset.pixelHeight),
            asset.hasAdjustments ? "adjusted" : "original",
            String(maximumLongEdge),
            String(format: "%.4f", jpegQuality)
        ]
        if let backgroundColor {
            fields.append(contentsOf: [
                String(backgroundColor.red),
                String(backgroundColor.green),
                String(backgroundColor.blue)
            ])
        }
        return fields.joined(separator: "|")
    }

    /// Searches messages for one whose caption contains a matching tag.
    static func findDuplicate(
        renderedHash: String,
        in messages: [SkylightResource<SkylightPhotoMessageAttributes>]
    ) -> String? {
        let shortHash = String(renderedHash.prefix(hashLength))
        for message in messages {
            if let hash = hash(fromCaption: message.attributes.caption), hash == shortHash {
                return message.id
            }
        }
        return nil
    }
}
