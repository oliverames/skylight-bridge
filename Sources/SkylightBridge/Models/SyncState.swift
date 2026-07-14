import Foundation

struct PhotoSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(mappingID.uuidString):\(appleAssetID)" }
    let mappingID: UUID
    var frameID = ""
    var destinationAlbumID = ""
    let appleAssetID: String
    var renderedHash: String
    var skylightMessageID: String
    var skylightAlbumIDs: Set<String>
    var lastSyncedAt: Date
}

struct ReminderSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(mappingID.uuidString):\(appleReminderID)" }
    let mappingID: UUID
    var frameID = ""
    var skylightListID = ""
    var appleReminderID: String
    var appleExternalID: String?
    var skylightItemID: String
    var lastAppleModifiedAt: Date
    var lastSkylightModifiedAt: Date
    var contentFingerprint: String
    // Last-synced field values for field-level two-way merge; absent in state
    // files written before merge support.
    var lastSyncedTitle: String?
    var lastSyncedCompleted: Bool?
    var tombstonedAt: Date?
}

struct NoteSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(kind.rawValue):\(appleNoteID)" }
    let kind: NotesContentKind
    var frameID = ""
    let appleNoteID: String
    var contentHash: String
    var skylightID: String
    var lastSyncedAt: Date
    // Two-way recipe fields; absent in state files written by 1.0.
    var lastAppleModifiedAt: Date?
    var lastSkylightUpdatedAt: String?
}

struct SyncState: Codable, Sendable {
    var photos: [PhotoSyncRecord] = []
    var reminders: [ReminderSyncRecord] = []
    var notes: [NoteSyncRecord] = []
}
