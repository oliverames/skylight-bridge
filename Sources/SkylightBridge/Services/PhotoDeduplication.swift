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
    /// caption does not contain one.
    static func hash(fromCaption caption: String?) -> String? {
        guard let caption else { return nil }
        guard let range = caption.range(of: tagPrefix) else { return nil }
        let afterPrefix = caption[range.upperBound...]
        guard let closeBracket = afterPrefix.firstIndex(of: "]") else { return nil }
        let extracted = String(afterPrefix[..<closeBracket])
        guard extracted.count == hashLength else { return nil }
        return extracted
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

    /// Strips the dedup tag from a caption for display.
    static func userVisibleCaption(_ caption: String?) -> String? {
        guard let caption else { return nil }
        guard let range = caption.range(of: tagPrefix) else { return caption }
        let stripped = String(caption[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Describes the Apple asset revision and the render settings that produce
    /// a converted image. Two runs that agree on this string cannot produce
    /// different JPEG bytes, so a sync can trust its stored hash and skip the
    /// render and encode entirely. Photos bumps `modificationDate` on any edit
    /// and `adjustmentDate` on an edit to the rendered appearance, and pixel
    /// dimensions catch a replaced original.
    static func sourceFingerprint(
        for asset: ApplePhotoAssetSnapshot,
        maximumLongEdge: Int,
        jpegQuality: Double
    ) -> String {
        let fields: [String] = [
            asset.id,
            asset.modificationDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "-",
            asset.adjustmentDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "-",
            String(asset.pixelWidth),
            String(asset.pixelHeight),
            asset.hasAdjustments ? "adjusted" : "original",
            String(maximumLongEdge),
            String(format: "%.4f", jpegQuality)
        ]
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
