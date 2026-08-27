import Foundation

enum SourceSelectionMode: String, Codable, CaseIterable, Sendable {
    case everything
    case selectedItems

    var label: String {
        switch self {
        case .everything: "Everything in source"
        case .selectedItems: "Only selected items"
        }
    }
}

enum PhotoSourceKind: String, Codable, CaseIterable, Sendable {
    case album
    case favorites
    case selectedPhotos

    var label: String {
        switch self {
        case .album: "Album or Folder"
        case .favorites: "Favorites"
        case .selectedPhotos: "Selected Photos"
        }
    }
}

enum ManagedRemovalPolicy: String, Codable, CaseIterable, Sendable {
    case keepOnSkylight
    case removeFromSkylight

    var label: String {
        switch self {
        case .keepOnSkylight: "Keep removed photos on Skylight"
        case .removeFromSkylight: "Remove bridge-managed copies"
        }
    }
}

struct PhotoMapping: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var name = "Photos"
    var sourceKind: PhotoSourceKind = .album
    var sourceCollectionID: String?
    var sourceCollectionTitle: String?
    var selectedAssetIDs: Set<String> = []
    /// Locally generated titles make the selected-photo list recognizable
    /// without changing anything in the person's Apple Photos library.
    var selectedPhotoNames: [String: String] = [:]
    var destinationAlbumID: String?
    var destinationAlbumTitle = "Apple Photos"
    var removalPolicy: ManagedRemovalPolicy = .removeFromSkylight
    var maximumLongEdge = 3_840
    var jpegQuality = 0.9
    var enabled = true
}

extension PhotoMapping {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceKind
        case sourceCollectionID
        case sourceCollectionTitle
        case selectedAssetIDs
        case selectedPhotoNames
        case destinationAlbumID
        case destinationAlbumTitle
        case removalPolicy
        case maximumLongEdge
        case jpegQuality
        case enabled
    }

    // Configurations from before selected-photo names existed must continue to
    // load instead of being replaced with an empty configuration.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Photos"
        sourceKind = try container.decodeIfPresent(PhotoSourceKind.self, forKey: .sourceKind) ?? .album
        sourceCollectionID = try container.decodeIfPresent(String.self, forKey: .sourceCollectionID)
        sourceCollectionTitle = try container.decodeIfPresent(String.self, forKey: .sourceCollectionTitle)
        selectedAssetIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedAssetIDs) ?? []
        selectedPhotoNames = try container.decodeIfPresent([String: String].self, forKey: .selectedPhotoNames) ?? [:]
        destinationAlbumID = try container.decodeIfPresent(String.self, forKey: .destinationAlbumID)
        destinationAlbumTitle = try container.decodeIfPresent(String.self, forKey: .destinationAlbumTitle) ?? "Apple Photos"
        removalPolicy = try container.decodeIfPresent(ManagedRemovalPolicy.self, forKey: .removalPolicy) ?? .removeFromSkylight
        maximumLongEdge = try container.decodeIfPresent(Int.self, forKey: .maximumLongEdge) ?? 3_840
        jpegQuality = try container.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 0.9
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct ReminderListMapping: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var sourceListID = ""
    var sourceListTitle = ""
    var selectionMode: SourceSelectionMode = .everything
    var selectedReminderIDs: Set<String> = []
    var destinationListID = ""
    var destinationListTitle = ""
    var destinationKind: SkylightListKind = .toDo
    var direction: ReminderSyncDirection = .appleToSkylight
    var conflictPolicy: SyncConflictPolicy = .newestWins
    var enabled = false
}

struct ChoreMemberLink: Identifiable, Codable, Sendable, Hashable {
    static let upForGrabsKey = "upForGrabs"

    var id: String { memberKey }
    var memberKey: String
    var memberLabel: String
    var appleListID: String?
    var appleListTitle: String
    var isEnabled: Bool

    init(
        memberKey: String,
        memberLabel: String,
        appleListID: String? = nil,
        appleListTitle: String? = nil,
        isEnabled: Bool = true
    ) {
        self.memberKey = memberKey
        self.memberLabel = memberLabel
        self.appleListID = appleListID
        self.appleListTitle = appleListTitle ?? "\(memberLabel) Chores"
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memberKey = try container.decode(String.self, forKey: .memberKey)
        memberLabel = try container.decodeIfPresent(String.self, forKey: .memberLabel) ?? memberKey
        appleListID = try container.decodeIfPresent(String.self, forKey: .appleListID)
        appleListTitle = try container.decodeIfPresent(String.self, forKey: .appleListTitle)
            ?? "\(memberLabel) Chores"
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

struct ChoreMapping: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var frameID = ""
    var frameName = ""
    var memberLinks: [ChoreMemberLink] = []
    var direction: ReminderSyncDirection = .twoWay
    var conflictPolicy: SyncConflictPolicy = .newestWins
    var isEnabled = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        frameID = try container.decodeIfPresent(String.self, forKey: .frameID) ?? ""
        frameName = try container.decodeIfPresent(String.self, forKey: .frameName) ?? ""
        memberLinks = try container.decodeIfPresent([ChoreMemberLink].self, forKey: .memberLinks) ?? []
        direction = try container.decodeIfPresent(ReminderSyncDirection.self, forKey: .direction) ?? .twoWay
        conflictPolicy = try container.decodeIfPresent(SyncConflictPolicy.self, forKey: .conflictPolicy) ?? .newestWins
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

enum NotesContentKind: String, Codable, CaseIterable, Sendable {
    case recipes
    case meals

    var label: String { rawValue.capitalized }
}

enum NotesSyncDirection: String, Codable, CaseIterable, Sendable {
    case appleToSkylight
    case twoWay

    var label: String {
        switch self {
        case .appleToSkylight: "Apple → Skylight"
        case .twoWay: "Two-way"
        }
    }
}

struct NotesSelection: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var kind: NotesContentKind
    var accountID: String?
    var folderID: String?
    var folderTitle: String?
    var selectionMode: SourceSelectionMode = .everything
    var selectedNoteIDs: Set<String> = []
    var destinationCategoryID: String?
    var direction: NotesSyncDirection = .appleToSkylight
    var conflictPolicy: SyncConflictPolicy = .newestWins
    var formattedNotes = true
    var enabled = false

    init(kind: NotesContentKind) {
        self.kind = kind
    }

    // Configurations written by 1.0 have no direction or conflict keys.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(NotesContentKind.self, forKey: .kind)
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        folderID = try container.decodeIfPresent(String.self, forKey: .folderID)
        folderTitle = try container.decodeIfPresent(String.self, forKey: .folderTitle)
        selectionMode = try container.decode(SourceSelectionMode.self, forKey: .selectionMode)
        selectedNoteIDs = try container.decode(Set<String>.self, forKey: .selectedNoteIDs)
        destinationCategoryID = try container.decodeIfPresent(
            String.self,
            forKey: .destinationCategoryID
        )
        direction = try container.decodeIfPresent(
            NotesSyncDirection.self,
            forKey: .direction
        ) ?? .appleToSkylight
        conflictPolicy = try container.decodeIfPresent(
            SyncConflictPolicy.self,
            forKey: .conflictPolicy
        ) ?? .newestWins
        formattedNotes = try container.decodeIfPresent(
            Bool.self,
            forKey: .formattedNotes
        ) ?? true
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }
}

struct SkylightAccountConfiguration: Codable, Sendable, Hashable {
    var baseURL = "https://app.ourskylight.com/api"
    var apiVersion = "2026-05-01"
    var frameID = ""
    var deviceID = ""
}

struct AppConfiguration: Codable, Sendable, Hashable {
    var account = SkylightAccountConfiguration()
    var photoMappings: [PhotoMapping] = []
    /// Mapping records removed on this Mac must not be re-created by an older
    /// CloudKit record. The shared package has no mapping tombstone yet, so the
    /// local configuration keeps a durable suppression set.
    var retiredPhotoMappingIDs: Set<UUID> = []
    /// CloudKit has no mapping-delete API. Keep the portable source record
    /// until a disabled replacement is confirmed in iCloud, so an offline
    /// deletion is retried after relaunch instead of remaining active elsewhere.
    var pendingPhotoMappingRetirements: [PhotoMapping] = []
    var reminderMappings: [ReminderListMapping] = []
    var choreMappings: [ChoreMapping] = []
    var recipeSelection = NotesSelection(kind: .recipes)
    var mealSelection = NotesSelection(kind: .meals)
    /// Fixed category choices are frame-scoped. The active selections above
    /// remain the UI's current values, while these dictionaries restore each
    /// frame's choice when the user returns to it.
    var recipeDestinationCategoryIDsByFrame: [String: String] = [:]
    var mealDestinationCategoryIDsByFrame: [String: String] = [:]
    /// Explicit destination choices are configuration, not sync history. IDs
    /// are stored by mapping and frame so a disabled or dry-run edit survives
    /// frame changes. Intent IDs distinguish a deliberate "New" choice from
    /// an identifier cleared only because the selected frame changed.
    var photoDestinationAlbumIDsByFrame: [String: String] = [:]
    var reminderDestinationListIDsByFrame: [String: String] = [:]
    var photoDestinationIntentIDsByFrame: [String: UUID] = [:]
    var reminderDestinationIntentIDsByFrame: [String: UUID] = [:]
    var syncIntervalMinutes = 15
    var dryRun = true
    var launchAtLogin = false
    // Absent in configuration files written before the Dock preference existed.
    var hideDockIcon = false

    static let empty = AppConfiguration()

    init() {}

    // Synthesized Codable requires every key regardless of property defaults.
    // Decode each field as optional so configurations written by older builds
    // keep loading (and are not silently replaced with .empty) after new
    // fields are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decodeIfPresent(
            SkylightAccountConfiguration.self, forKey: .account
        ) ?? SkylightAccountConfiguration()
        photoMappings = try container.decodeIfPresent(
            [PhotoMapping].self, forKey: .photoMappings
        ) ?? []
        retiredPhotoMappingIDs = try container.decodeIfPresent(
            Set<UUID>.self, forKey: .retiredPhotoMappingIDs
        ) ?? []
        pendingPhotoMappingRetirements = try container.decodeIfPresent(
            [PhotoMapping].self, forKey: .pendingPhotoMappingRetirements
        ) ?? []
        reminderMappings = try container.decodeIfPresent(
            [ReminderListMapping].self, forKey: .reminderMappings
        ) ?? []
        choreMappings = try container.decodeIfPresent(
            [ChoreMapping].self, forKey: .choreMappings
        ) ?? []
        recipeSelection = try container.decodeIfPresent(
            NotesSelection.self, forKey: .recipeSelection
        ) ?? NotesSelection(kind: .recipes)
        mealSelection = try container.decodeIfPresent(
            NotesSelection.self, forKey: .mealSelection
        ) ?? NotesSelection(kind: .meals)
        recipeDestinationCategoryIDsByFrame = try container.decodeIfPresent(
            [String: String].self,
            forKey: .recipeDestinationCategoryIDsByFrame
        ) ?? [:]
        mealDestinationCategoryIDsByFrame = try container.decodeIfPresent(
            [String: String].self,
            forKey: .mealDestinationCategoryIDsByFrame
        ) ?? [:]
        photoDestinationAlbumIDsByFrame = try container.decodeIfPresent(
            [String: String].self,
            forKey: .photoDestinationAlbumIDsByFrame
        ) ?? [:]
        reminderDestinationListIDsByFrame = try container.decodeIfPresent(
            [String: String].self,
            forKey: .reminderDestinationListIDsByFrame
        ) ?? [:]
        photoDestinationIntentIDsByFrame = try container.decodeIfPresent(
            [String: UUID].self,
            forKey: .photoDestinationIntentIDsByFrame
        ) ?? [:]
        reminderDestinationIntentIDsByFrame = try container.decodeIfPresent(
            [String: UUID].self,
            forKey: .reminderDestinationIntentIDsByFrame
        ) ?? [:]
        syncIntervalMinutes = try container.decodeIfPresent(
            Int.self, forKey: .syncIntervalMinutes
        ) ?? 15
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hideDockIcon = try container.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false
    }

    var hasEnabledSync: Bool {
        photoMappings.contains(where: \.enabled) ||
            reminderMappings.contains(where: \.enabled) ||
            choreMappings.contains { mapping in
                mapping.isEnabled && mapping.memberLinks.contains(where: \.isEnabled)
            } ||
            (recipeSelection.enabled && recipeSelection.folderID != nil) ||
            (mealSelection.enabled && mealSelection.folderID != nil)
    }
}

enum FrameDestinationIdentity {
    static func key(mappingID: UUID, frameID: String) -> String {
        "\(mappingID.uuidString)|\(frameID.trimmed)"
    }

    static func belongsToMapping(_ key: String, mappingID: UUID) -> Bool {
        key.hasPrefix("\(mappingID.uuidString)|")
    }
}
