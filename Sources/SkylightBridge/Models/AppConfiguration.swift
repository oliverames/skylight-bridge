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
    var destinationAlbumID: String?
    var destinationAlbumTitle = "Apple Photos"
    var removalPolicy: ManagedRemovalPolicy = .removeFromSkylight
    var maximumLongEdge = 3_840
    var jpegQuality = 0.9
    var enabled = true
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
    var reminderMappings: [ReminderListMapping] = []
    var recipeSelection = NotesSelection(kind: .recipes)
    var mealSelection = NotesSelection(kind: .meals)
    var syncIntervalMinutes = 15
    var dryRun = true
    var launchAtLogin = false

    static let empty = AppConfiguration()

    var hasEnabledSync: Bool {
        photoMappings.contains(where: \.enabled) ||
            reminderMappings.contains(where: \.enabled) ||
            (recipeSelection.enabled && recipeSelection.folderID != nil) ||
            (mealSelection.enabled && mealSelection.folderID != nil)
    }
}
