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
    /// Captions are a Skylight-only photo field. Retaining the last value lets
    /// a selected-photo name update its existing remote message without an
    /// unnecessary re-upload.
    var lastSyncedCaption: String?
    /// Identifies the Apple asset revision and the render settings that
    /// produced `renderedHash`. When it still matches, the photo cannot have
    /// changed, so a sync skips the expensive render and JPEG encode instead of
    /// redoing them only to compare hashes. Absent in state written before
    /// this field existed, which simply means the first run re-renders once.
    var sourceFingerprint: String?

    init(
        mappingID: UUID,
        frameID: String = "",
        destinationAlbumID: String = "",
        appleAssetID: String,
        renderedHash: String,
        skylightMessageID: String,
        skylightAlbumIDs: Set<String>,
        lastSyncedAt: Date,
        lastSyncedCaption: String? = nil,
        sourceFingerprint: String? = nil
    ) {
        self.mappingID = mappingID
        self.frameID = frameID
        self.destinationAlbumID = destinationAlbumID
        self.appleAssetID = appleAssetID
        self.renderedHash = renderedHash
        self.skylightMessageID = skylightMessageID
        self.skylightAlbumIDs = skylightAlbumIDs
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedCaption = lastSyncedCaption
        self.sourceFingerprint = sourceFingerprint
    }

    // Persisted struct: synthesized decoding throws on any missing key, so a
    // field added in a future version would make older state files unreadable.
    // Identity fields stay strict; everything else falls back per field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappingID = try container.decode(UUID.self, forKey: .mappingID)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID) ?? ""
        destinationAlbumID = try container.decodeIfPresent(String.self, forKey: .destinationAlbumID) ?? ""
        appleAssetID = try container.decode(String.self, forKey: .appleAssetID)
        renderedHash = try container.decodeIfPresent(String.self, forKey: .renderedHash) ?? ""
        skylightMessageID = try container.decodeIfPresent(String.self, forKey: .skylightMessageID) ?? ""
        skylightAlbumIDs = try container.decodeIfPresent(Set<String>.self, forKey: .skylightAlbumIDs) ?? []
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt) ?? .distantPast
        lastSyncedCaption = try container.decodeIfPresent(String.self, forKey: .lastSyncedCaption)
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint)
    }
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

    init(
        mappingID: UUID,
        frameID: String = "",
        skylightListID: String = "",
        appleReminderID: String,
        appleExternalID: String? = nil,
        skylightItemID: String,
        lastAppleModifiedAt: Date,
        lastSkylightModifiedAt: Date,
        contentFingerprint: String,
        lastSyncedTitle: String? = nil,
        lastSyncedCompleted: Bool? = nil,
        tombstonedAt: Date? = nil
    ) {
        self.mappingID = mappingID
        self.frameID = frameID
        self.skylightListID = skylightListID
        self.appleReminderID = appleReminderID
        self.appleExternalID = appleExternalID
        self.skylightItemID = skylightItemID
        self.lastAppleModifiedAt = lastAppleModifiedAt
        self.lastSkylightModifiedAt = lastSkylightModifiedAt
        self.contentFingerprint = contentFingerprint
        self.lastSyncedTitle = lastSyncedTitle
        self.lastSyncedCompleted = lastSyncedCompleted
        self.tombstonedAt = tombstonedAt
    }

    // Persisted struct: decode per field so future additions never strand old
    // state files (see PhotoSyncRecord).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappingID = try container.decode(UUID.self, forKey: .mappingID)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID) ?? ""
        skylightListID = try container.decodeIfPresent(String.self, forKey: .skylightListID) ?? ""
        appleReminderID = try container.decode(String.self, forKey: .appleReminderID)
        appleExternalID = try container.decodeIfPresent(String.self, forKey: .appleExternalID)
        skylightItemID = try container.decodeIfPresent(String.self, forKey: .skylightItemID) ?? ""
        lastAppleModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastAppleModifiedAt) ?? .distantPast
        lastSkylightModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastSkylightModifiedAt) ?? .distantPast
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint) ?? ""
        lastSyncedTitle = try container.decodeIfPresent(String.self, forKey: .lastSyncedTitle)
        lastSyncedCompleted = try container.decodeIfPresent(Bool.self, forKey: .lastSyncedCompleted)
        tombstonedAt = try container.decodeIfPresent(Date.self, forKey: .tombstonedAt)
    }
}

/// Baselines for the portable list-name field. Apple and Skylight do not
/// expose mutable-list timestamps, so each side keeps its own last-seen title
/// and the coordinator can determine which side changed on the next sync.
struct ReminderListSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(mappingID.uuidString):\(appleListID):\(skylightListID)" }
    let mappingID: UUID
    var frameID: String
    var appleListID: String
    var skylightListID: String
    var lastSyncedAppleTitle: String
    var lastSyncedSkylightTitle: String
    var lastSyncedAppleColor: String?
    var lastSyncedSkylightColor: String?

    init(
        mappingID: UUID,
        frameID: String,
        appleListID: String,
        skylightListID: String,
        lastSyncedAppleTitle: String,
        lastSyncedSkylightTitle: String,
        lastSyncedAppleColor: String? = nil,
        lastSyncedSkylightColor: String? = nil
    ) {
        self.mappingID = mappingID
        self.frameID = frameID
        self.appleListID = appleListID
        self.skylightListID = skylightListID
        self.lastSyncedAppleTitle = lastSyncedAppleTitle
        self.lastSyncedSkylightTitle = lastSyncedSkylightTitle
        self.lastSyncedAppleColor = lastSyncedAppleColor
        self.lastSyncedSkylightColor = lastSyncedSkylightColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappingID = try container.decode(UUID.self, forKey: .mappingID)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID) ?? ""
        appleListID = try container.decodeIfPresent(String.self, forKey: .appleListID) ?? ""
        skylightListID = try container.decodeIfPresent(String.self, forKey: .skylightListID) ?? ""
        lastSyncedAppleTitle = try container.decodeIfPresent(
            String.self, forKey: .lastSyncedAppleTitle
        ) ?? ""
        lastSyncedSkylightTitle = try container.decodeIfPresent(
            String.self, forKey: .lastSyncedSkylightTitle
        ) ?? ""
        lastSyncedAppleColor = try container.decodeIfPresent(
            String.self, forKey: .lastSyncedAppleColor
        )
        lastSyncedSkylightColor = try container.decodeIfPresent(
            String.self, forKey: .lastSyncedSkylightColor
        )
    }
}

struct ChoreSyncRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(mappingID.uuidString):\(appleReminderID)" }
    let mappingID: UUID
    var frameID: String
    var appleReminderID: String
    var skylightSeriesID: String
    var memberKey: String
    var lastAppleModifiedAt: Date
    var lastSkylightModifiedAt: Date
    var contentFingerprint: String
    var lastSyncedTitle: String?
    var lastSyncedNotes: String?
    var lastSyncedRecurrence: String?
    var baselineDueDate: Date?
    var baselineCompletedInstanceDate: String?
    var recurrenceDegraded: Bool

    init(
        mappingID: UUID,
        frameID: String,
        appleReminderID: String,
        skylightSeriesID: String,
        memberKey: String,
        lastAppleModifiedAt: Date,
        lastSkylightModifiedAt: Date,
        contentFingerprint: String,
        lastSyncedTitle: String? = nil,
        lastSyncedNotes: String? = nil,
        lastSyncedRecurrence: String? = nil,
        baselineDueDate: Date? = nil,
        baselineCompletedInstanceDate: String? = nil,
        recurrenceDegraded: Bool = false
    ) {
        self.mappingID = mappingID
        self.frameID = frameID
        self.appleReminderID = appleReminderID
        self.skylightSeriesID = skylightSeriesID
        self.memberKey = memberKey
        self.lastAppleModifiedAt = lastAppleModifiedAt
        self.lastSkylightModifiedAt = lastSkylightModifiedAt
        self.contentFingerprint = contentFingerprint
        self.lastSyncedTitle = lastSyncedTitle
        self.lastSyncedNotes = lastSyncedNotes
        self.lastSyncedRecurrence = lastSyncedRecurrence
        self.baselineDueDate = baselineDueDate
        self.baselineCompletedInstanceDate = baselineCompletedInstanceDate
        self.recurrenceDegraded = recurrenceDegraded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappingID = try container.decode(UUID.self, forKey: .mappingID)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID) ?? ""
        appleReminderID = try container.decode(String.self, forKey: .appleReminderID)
        skylightSeriesID = try container.decodeIfPresent(String.self, forKey: .skylightSeriesID) ?? ""
        memberKey = try container.decodeIfPresent(String.self, forKey: .memberKey) ?? ""
        lastAppleModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastAppleModifiedAt) ?? .distantPast
        lastSkylightModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastSkylightModifiedAt) ?? .distantPast
        contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint) ?? ""
        lastSyncedTitle = try container.decodeIfPresent(String.self, forKey: .lastSyncedTitle)
        lastSyncedNotes = try container.decodeIfPresent(String.self, forKey: .lastSyncedNotes)
        lastSyncedRecurrence = try container.decodeIfPresent(String.self, forKey: .lastSyncedRecurrence)
        baselineDueDate = try container.decodeIfPresent(Date.self, forKey: .baselineDueDate)
        baselineCompletedInstanceDate = try container.decodeIfPresent(String.self, forKey: .baselineCompletedInstanceDate)
        recurrenceDegraded = try container.decodeIfPresent(Bool.self, forKey: .recurrenceDegraded) ?? false
    }
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
    // Category and title emoji the on-device classifier chose while the
    // mapping is set to Automatic; nil means not classified yet. The emoji is
    // cached so note-driven pushes re-apply it without re-running the model.
    var autoCategoryID: String?
    var autoEmoji: String?

    init(
        kind: NotesContentKind,
        frameID: String = "",
        appleNoteID: String,
        contentHash: String,
        skylightID: String,
        lastSyncedAt: Date,
        lastAppleModifiedAt: Date? = nil,
        lastSkylightUpdatedAt: String? = nil,
        autoCategoryID: String? = nil,
        autoEmoji: String? = nil
    ) {
        self.kind = kind
        self.frameID = frameID
        self.appleNoteID = appleNoteID
        self.contentHash = contentHash
        self.skylightID = skylightID
        self.lastSyncedAt = lastSyncedAt
        self.lastAppleModifiedAt = lastAppleModifiedAt
        self.lastSkylightUpdatedAt = lastSkylightUpdatedAt
        self.autoCategoryID = autoCategoryID
        self.autoEmoji = autoEmoji
    }

    // Persisted struct: decode per field so future additions never strand old
    // state files (see PhotoSyncRecord).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(NotesContentKind.self, forKey: .kind)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID) ?? ""
        appleNoteID = try container.decode(String.self, forKey: .appleNoteID)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash) ?? ""
        skylightID = try container.decodeIfPresent(String.self, forKey: .skylightID) ?? ""
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt) ?? .distantPast
        lastAppleModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastAppleModifiedAt)
        lastSkylightUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastSkylightUpdatedAt)
        autoCategoryID = try container.decodeIfPresent(String.self, forKey: .autoCategoryID)
        autoEmoji = try container.decodeIfPresent(String.self, forKey: .autoEmoji)
    }
}

/// A Skylight album that the bridge created for a mapping. Only bridge-created
/// albums are recorded, so mapping deletion never removes an album the user
/// pointed the mapping at.
struct PhotoAlbumRecord: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(mappingID.uuidString):\(albumID)" }
    let mappingID: UUID
    var frameID = ""
    let albumID: String

    init(mappingID: UUID, frameID: String = "", albumID: String) {
        self.mappingID = mappingID
        self.frameID = frameID
        self.albumID = albumID
    }

    // Persisted struct: decode per field so future additions never strand old
    // state files (see PhotoSyncRecord).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappingID = try container.decode(UUID.self, forKey: .mappingID)
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID) ?? ""
        albumID = try container.decode(String.self, forKey: .albumID)
    }
}

struct SyncState: Codable, Sendable {
    var photos: [PhotoSyncRecord] = []
    var reminders: [ReminderSyncRecord] = []
    var reminderLists: [ReminderListSyncRecord] = []
    var chores: [ChoreSyncRecord] = []
    var notes: [NoteSyncRecord] = []
    // Absent in state files written before album tracking existed.
    var photoAlbums: [PhotoAlbumRecord] = []
    // Frames whose recipe records have had wrongly cached fallback categories
    // cleared (one-time repair; see syncRecipes). Absent before 1.4.1.
    var recipeFallbackCacheClearedFrameIDs: Set<String> = []

    init() {}

    // Synthesized Codable requires every key regardless of property defaults,
    // so decode each section as optional to keep older state files loadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        photos = try container.decodeIfPresent([PhotoSyncRecord].self, forKey: .photos) ?? []
        reminders = try container.decodeIfPresent([ReminderSyncRecord].self, forKey: .reminders) ?? []
        reminderLists = try container.decodeIfPresent([ReminderListSyncRecord].self, forKey: .reminderLists) ?? []
        chores = try container.decodeIfPresent([ChoreSyncRecord].self, forKey: .chores) ?? []
        notes = try container.decodeIfPresent([NoteSyncRecord].self, forKey: .notes) ?? []
        photoAlbums = try container.decodeIfPresent([PhotoAlbumRecord].self, forKey: .photoAlbums) ?? []
        recipeFallbackCacheClearedFrameIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .recipeFallbackCacheClearedFrameIDs
        ) ?? []
    }
}
