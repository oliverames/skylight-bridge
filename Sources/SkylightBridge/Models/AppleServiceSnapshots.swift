import CoreGraphics
import Foundation

enum ApplePhotoCollectionKind: String, Sendable, Codable {
    case album
    case favorites
    case folder
    case smartAlbum
}

enum ApplePhotosAuthorizationStatus: String, Sendable, Codable {
    case notDetermined
    case restricted
    case denied
    case fullAccess
    case limited
    case unknown
}

struct ApplePhotoCollectionSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let kind: ApplePhotoCollectionKind
    let parentID: String?
}

enum ApplePhotoMediaKind: String, Sendable, Codable {
    case image
    case livePhoto
    case video
    case unknown
}

struct ApplePhotoAssetSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let mediaKind: ApplePhotoMediaKind
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let modificationDate: Date?
    let adjustmentDate: Date?
    let contentTypeIdentifier: String?
    let isFavorite: Bool
    let isHidden: Bool
    let hasAdjustments: Bool
}

struct AppleRenderedPhoto: Sendable {
    let asset: ApplePhotoAssetSnapshot
    let image: CGImage
}

struct AppleRGBColor: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = AppleRGBColor(red: 1, green: 1, blue: 1)
}

struct AppleImageConversionOptions: Sendable, Hashable {
    let maximumLongEdge: Int
    let jpegQuality: Double
    let backgroundColor: AppleRGBColor

    init(
        maximumLongEdge: Int = 3_840,
        jpegQuality: Double = 0.9,
        backgroundColor: AppleRGBColor = .white
    ) {
        self.maximumLongEdge = maximumLongEdge
        self.jpegQuality = jpegQuality
        self.backgroundColor = backgroundColor
    }
}

struct AppleConvertedImage: Sendable, Hashable {
    let assetID: String
    let data: Data
    let typeIdentifier: String
    let pixelWidth: Int
    let pixelHeight: Int
    let sha256: String
}

enum AppleRemindersAuthorizationStatus: String, Sendable, Codable {
    case notDetermined
    case restricted
    case denied
    case fullAccess
    case writeOnly
    case unknown
}

struct AppleReminderListSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let sourceID: String
    let sourceTitle: String
    let allowsContentModifications: Bool
}

struct AppleReminderSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let externalID: String?
    let listID: String
    let listTitle: String
    let title: String
    let notes: String?
    let url: URL?
    let isCompleted: Bool
    let completionDate: Date?
    let startDateComponents: DateComponents?
    let dueDateComponents: DateComponents?
    let priority: Int
    let creationDate: Date?
    let modificationDate: Date?
    let hasRecurrenceRules: Bool
}

struct AppleReminderDraft: Sendable, Hashable {
    let title: String
    let notes: String?
    let url: URL?
    let startDateComponents: DateComponents?
    let dueDateComponents: DateComponents?
    let priority: Int
    let isCompleted: Bool

    init(
        title: String,
        notes: String? = nil,
        url: URL? = nil,
        startDateComponents: DateComponents? = nil,
        dueDateComponents: DateComponents? = nil,
        priority: Int = 0,
        isCompleted: Bool = false
    ) {
        self.title = title
        self.notes = notes
        self.url = url
        self.startDateComponents = startDateComponents
        self.dueDateComponents = dueDateComponents
        self.priority = priority
        self.isCompleted = isCompleted
    }
}

enum AppleNullableUpdate<Value: Sendable>: Sendable {
    case unchanged
    case set(Value)
    case clear
}

struct AppleReminderPatch: Sendable {
    var title: String?
    var notes: AppleNullableUpdate<String>
    var url: AppleNullableUpdate<URL>
    var startDateComponents: AppleNullableUpdate<DateComponents>
    var dueDateComponents: AppleNullableUpdate<DateComponents>
    var priority: Int?
    var isCompleted: Bool?

    init(
        title: String? = nil,
        notes: AppleNullableUpdate<String> = .unchanged,
        url: AppleNullableUpdate<URL> = .unchanged,
        startDateComponents: AppleNullableUpdate<DateComponents> = .unchanged,
        dueDateComponents: AppleNullableUpdate<DateComponents> = .unchanged,
        priority: Int? = nil,
        isCompleted: Bool? = nil
    ) {
        self.title = title
        self.notes = notes
        self.url = url
        self.startDateComponents = startDateComponents
        self.dueDateComponents = dueDateComponents
        self.priority = priority
        self.isCompleted = isCompleted
    }
}

struct AppleNotesAccountSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
}

struct AppleNotesFolderSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let accountID: String
    let parentFolderID: String?
    let isShared: Bool
}

struct AppleNoteAttachmentSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let contentIdentifier: String
    let url: URL?
    let creationDate: Date?
    let modificationDate: Date?
    let isShared: Bool
}

struct AppleNoteSummarySnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let folderID: String
    let title: String
    let creationDate: Date?
    let modificationDate: Date?
    let isPasswordProtected: Bool
    let isShared: Bool
    let attachmentCount: Int
}

struct AppleNoteSnapshot: Identifiable, Sendable, Hashable {
    let id: String
    let folderID: String
    let title: String
    let bodyHTML: String
    let plaintext: String
    let creationDate: Date?
    let modificationDate: Date?
    let isPasswordProtected: Bool
    let isShared: Bool
    let attachments: [AppleNoteAttachmentSnapshot]
}

struct AppleSourceChange: Sendable, Hashable {
    let occurredAt: Date
}
