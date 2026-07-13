import Foundation

struct PhotoSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(mappingID.uuidString):\(appleAssetID)" }
    let mappingID: UUID
    let appleAssetID: String
    var renderedHash: String
    var skylightMessageID: String
    var skylightAlbumIDs: Set<String>
    var lastSyncedAt: Date
}

struct ReminderSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(mappingID.uuidString):\(appleReminderID)" }
    let mappingID: UUID
    var appleReminderID: String
    var appleExternalID: String?
    var skylightItemID: String
    var lastAppleModifiedAt: Date
    var lastSkylightModifiedAt: Date
    var contentFingerprint: String
    var tombstonedAt: Date?
}

struct NoteSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(kind.rawValue):\(appleNoteID)" }
    let kind: NotesContentKind
    let appleNoteID: String
    var contentHash: String
    var skylightID: String
    var lastSyncedAt: Date
}

struct SyncState: Codable, Sendable {
    var photos: [PhotoSyncRecord] = []
    var reminders: [ReminderSyncRecord] = []
    var notes: [NoteSyncRecord] = []
}
