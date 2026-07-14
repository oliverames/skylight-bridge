import CryptoKit
import Foundation

struct SyncDomainSummary: Equatable, Sendable {
    var planned = 0
    var applied = 0
}

struct SyncRunSummary: Equatable, Sendable {
    let dryRun: Bool
    var photos = SyncDomainSummary()
    var reminders = SyncDomainSummary()
    var recipes = SyncDomainSummary()
    var meals = SyncDomainSummary()

    var totalPlanned: Int {
        photos.planned + reminders.planned + recipes.planned + meals.planned
    }

    var totalApplied: Int {
        photos.applied + reminders.applied + recipes.applied + meals.applied
    }
}

enum SyncCoordinatorError: Error, LocalizedError, Sendable {
    case missingFrameID
    case missingPhotoCollection(UUID)
    case missingPhotoDestination(UUID)
    case invalidPhotoDestination(UUID)
    case ambiguousPhotoDestination(String)
    case missingNotesFolder(NotesContentKind)
    case invalidUploadURL
    case missingUploadMessageID
    case convertedImageTooLarge(assetID: String, bytes: Int)
    case photoCollectionTooLarge(count: Int, maximum: Int)
    case photoProcessingTimedOut(String)
    case photoProcessingFailed(messageID: String, status: String)
    case unsupportedMealDay(String)
    case invalidMealReference(String)
    case missingReminderDestination(UUID)
    case invalidReminderDestination(UUID)
    case ambiguousReminderDestination(String)
    case missingMealCategory(NotesContentKind)
    case invalidMealCategory(NotesContentKind)

    var errorDescription: String? {
        switch self {
        case .missingFrameID:
            "A Skylight frame must be selected before synchronization."
        case .missingPhotoCollection:
            "A photo mapping does not have a usable source collection."
        case .missingPhotoDestination:
            "A photo mapping does not have a usable destination album."
        case .invalidPhotoDestination:
            "A photo mapping refers to an album that is not available on the selected frame."
        case let .ambiguousPhotoDestination(title):
            "More than one Skylight album is named ‘\(title)’. Choose a specific destination album."
        case let .missingNotesFolder(kind):
            "The enabled \(kind.rawValue) selection does not have an Apple Notes folder."
        case .invalidUploadURL:
            "Skylight returned an invalid photo upload destination."
        case .missingUploadMessageID:
            "Skylight did not return a message identifier for the photo upload."
        case let .convertedImageTooLarge(assetID, bytes):
            "Converted photo \(assetID) is \(bytes) bytes, above the 25 MB upload limit."
        case let .photoCollectionTooLarge(count, maximum):
            "The selected photo source contains \(count) items. Select \(maximum) or fewer for one mapping."
        case let .photoProcessingTimedOut(messageID):
            "Skylight did not finish processing uploaded photo \(messageID) in time."
        case let .photoProcessingFailed(messageID, status):
            "Skylight could not process uploaded photo \(messageID): \(status)."
        case let .unsupportedMealDay(day):
            "The meal day '\(day)' is not an ISO date or weekday name."
        case let .invalidMealReference(value):
            "The stored meal reference is invalid: \(value)"
        case .missingReminderDestination:
            "A reminder mapping does not have a Skylight list name or ID."
        case .invalidReminderDestination:
            "A reminder mapping refers to a list that is not available on the selected frame."
        case let .ambiguousReminderDestination(title):
            "More than one Skylight list is named ‘\(title)’. Choose a specific destination list."
        case let .missingMealCategory(kind):
            "Skylight does not have a meal category available for \(kind.rawValue)."
        case let .invalidMealCategory(kind):
            "The selected Skylight meal category is not available for \(kind.rawValue)."
        }
    }
}

@MainActor
protocol PhotoSyncSource: Sendable {
    func syncPhotoCollections() async throws -> [ApplePhotoCollectionSnapshot]
    func syncPhotoAssets(in collectionID: String) async throws -> [ApplePhotoAssetSnapshot]
    func syncPhotoAssets(withIDs assetIDs: [String]) async throws -> [ApplePhotoAssetSnapshot]
    func syncRenderedPhoto(withID assetID: String, maximumLongEdge: Int) async throws -> AppleRenderedPhoto
}

@MainActor
protocol ReminderSyncSource: Sendable {
    func syncReminders(in listID: String) async throws -> [AppleReminderSnapshot]
    func syncCreateReminder(in listID: String, draft: AppleReminderDraft) async throws -> AppleReminderSnapshot
    func syncUpdateReminder(withID reminderID: String, patch: AppleReminderPatch) async throws -> AppleReminderSnapshot
    func syncRemoveReminder(withID reminderID: String) async throws
}

protocol NotesSyncSource: Sendable {
    func syncNoteSummaries(inFolderID folderID: String) async throws -> [AppleNoteSummarySnapshot]
    func syncNote(withID noteID: String, inFolderID folderID: String) async throws -> AppleNoteSnapshot
    func syncCreateNote(inFolderID folderID: String, bodyHTML: String) async throws -> String
    func syncUpdateNote(
        withID noteID: String,
        inFolderID folderID: String,
        bodyHTML: String
    ) async throws
    func syncTrashNote(withID noteID: String, inFolderID folderID: String) async throws
}

protocol SyncImageConverting: Sendable {
    func syncConvert(
        _ renderedPhoto: AppleRenderedPhoto,
        options: AppleImageConversionOptions
    ) async throws -> AppleConvertedImage
}

protocol SyncStatePersisting: Sendable {
    func loadSyncState() async throws -> SyncState
    func saveSyncState(_ state: SyncState) async throws
}

protocol MealDateResolving: Sendable {
    func resolveMealDate(_ day: String, relativeTo now: Date) throws -> String
}

protocol SkylightSyncAPI: Sendable {
    func listAlbums(frameID: String) async throws -> [SkylightResource<SkylightAlbumAttributes>]
    func createAlbum(
        frameID: String,
        title: String
    ) async throws -> SkylightResource<SkylightAlbumAttributes>
    func deleteAlbum(frameID: String, albumID: String) async throws
    func listAllAlbumMessageIDs(frameID: String, albumID: String) async throws -> [String]
    func requestUploadURL(
        ext: String,
        frameIDs: [String],
        caption: String?
    ) async throws -> SkylightUploadURLAttributes
    func upload(data: Data, to presignedURL: URL, contentType: String) async throws
    func addMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws
    func removeMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws
    func deleteMessage(frameID: String, messageID: String) async throws
    func getMessage(
        frameID: String,
        messageID: String
    ) async throws -> SkylightResource<SkylightPhotoMessageAttributes>
    func listMessages(
        frameID: String,
        page: Int?,
        syncToken: String?,
        pageToken: String?
    ) async throws -> SkylightPhotoMessagesResponse

    func listLists(frameID: String) async throws -> SkylightListCollectionResponse
    func createList(
        frameID: String,
        request: SkylightListRequest
    ) async throws -> SkylightResource<SkylightListAttributes>

    func listListItems(
        frameID: String,
        listID: String
    ) async throws -> [SkylightResource<SkylightListItemAttributes>]
    func createListItem(
        frameID: String,
        listID: String,
        request: SkylightListItemRequest
    ) async throws -> SkylightResource<SkylightListItemAttributes>
    func updateListItem(
        frameID: String,
        listID: String,
        itemID: String,
        request: SkylightListItemRequest
    ) async throws -> SkylightResource<SkylightListItemAttributes>
    func deleteListItem(frameID: String, listID: String, itemID: String) async throws

    func createRecipe(
        frameID: String,
        request: SkylightRecipeRequest
    ) async throws -> SkylightResource<SkylightRecipeAttributes>
    func updateRecipe(
        frameID: String,
        recipeID: String,
        request: SkylightRecipeRequest
    ) async throws -> SkylightResource<SkylightRecipeAttributes>
    func listRecipes(frameID: String) async throws -> [SkylightResource<SkylightRecipeAttributes>]
    func deleteRecipe(frameID: String, recipeID: String, applyToSittings: Bool) async throws
    func listMealCategories(
        frameID: String
    ) async throws -> [SkylightResource<SkylightMealCategoryAttributes>]

    func createMealSitting(
        frameID: String,
        request: SkylightMealSittingRequest
    ) async throws -> SkylightResource<SkylightMealSittingAttributes>
    func updateMealInstance(
        frameID: String,
        mealID: String,
        instanceISO: String,
        request: SkylightMealInstanceUpdateRequest
    ) async throws -> SkylightResource<SkylightMealSittingAttributes>
    func deleteMealInstance(
        frameID: String,
        mealID: String,
        instanceISO: String,
        applyTo: String?
    ) async throws
}

extension ApplePhotoLibrary: PhotoSyncSource {
    func syncPhotoCollections() async throws -> [ApplePhotoCollectionSnapshot] {
        try collections()
    }

    func syncPhotoAssets(in collectionID: String) async throws -> [ApplePhotoAssetSnapshot] {
        try assets(in: collectionID)
    }

    func syncPhotoAssets(withIDs assetIDs: [String]) async throws -> [ApplePhotoAssetSnapshot] {
        try assets(withIDs: assetIDs)
    }

    func syncRenderedPhoto(
        withID assetID: String,
        maximumLongEdge: Int
    ) async throws -> AppleRenderedPhoto {
        try await renderedPhoto(withID: assetID, maximumLongEdge: maximumLongEdge)
    }
}

extension AppleRemindersStore: ReminderSyncSource {
    func syncReminders(in listID: String) async throws -> [AppleReminderSnapshot] {
        try await reminders(in: listID)
    }

    func syncCreateReminder(
        in listID: String,
        draft: AppleReminderDraft
    ) async throws -> AppleReminderSnapshot {
        try createReminder(in: listID, draft: draft)
    }

    func syncUpdateReminder(
        withID reminderID: String,
        patch: AppleReminderPatch
    ) async throws -> AppleReminderSnapshot {
        try updateReminder(withID: reminderID, patch: patch)
    }

    func syncRemoveReminder(withID reminderID: String) async throws {
        try removeReminder(withID: reminderID)
    }
}

extension AppleNotesStore: NotesSyncSource {
    func syncNoteSummaries(inFolderID folderID: String) async throws -> [AppleNoteSummarySnapshot] {
        try noteSummaries(inFolderID: folderID)
    }

    func syncNote(withID noteID: String, inFolderID folderID: String) async throws -> AppleNoteSnapshot {
        try note(withID: noteID, inFolderID: folderID)
    }

    func syncCreateNote(inFolderID folderID: String, bodyHTML: String) async throws -> String {
        try createNote(inFolderID: folderID, bodyHTML: bodyHTML)
    }

    func syncUpdateNote(
        withID noteID: String,
        inFolderID folderID: String,
        bodyHTML: String
    ) async throws {
        try updateNote(withID: noteID, inFolderID: folderID, bodyHTML: bodyHTML)
    }

    func syncTrashNote(withID noteID: String, inFolderID folderID: String) async throws {
        try trashNote(withID: noteID, inFolderID: folderID)
    }
}

extension ImageConversionService: SyncImageConverting {
    func syncConvert(
        _ renderedPhoto: AppleRenderedPhoto,
        options: AppleImageConversionOptions
    ) async throws -> AppleConvertedImage {
        try convert(renderedPhoto, options: options)
    }
}

extension SyncStateStore: SyncStatePersisting {
    func loadSyncState() async throws -> SyncState {
        try load()
    }

    func saveSyncState(_ state: SyncState) async throws {
        try save(state)
    }
}

extension SkylightAPIClient: SkylightSyncAPI {}

struct DefaultMealDateResolver: MealDateResolving {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    func resolveMealDate(_ day: String, relativeTo now: Date) throws -> String {
        let value = day.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isISODate(value, calendar: calendar) {
            return value
        }

        let weekday = Self.weekdayNumber(for: value)
        guard let weekday else {
            throw SyncCoordinatorError.unsupportedMealDay(day)
        }

        let start = calendar.startOfDay(for: now)
        let currentWeekday = calendar.component(.weekday, from: start)
        let daysAhead = (weekday - currentWeekday + 7) % 7
        guard let resolved = calendar.date(byAdding: .day, value: daysAhead, to: start) else {
            throw SyncCoordinatorError.unsupportedMealDay(day)
        }

        return Self.isoDate(resolved, calendar: calendar)
    }

    private static func isISODate(_ value: String, calendar: Calendar) -> Bool {
        guard value.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { isoDate($0, calendar: calendar) == value } ?? false
    }

    private static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func weekdayNumber(for value: String) -> Int? {
        switch value.lowercased() {
        case "sunday", "sun": 1
        case "monday", "mon": 2
        case "tuesday", "tue", "tues": 3
        case "wednesday", "wed": 4
        case "thursday", "thu", "thur", "thurs": 5
        case "friday", "fri": 6
        case "saturday", "sat": 7
        default: nil
        }
    }
}

actor SyncCoordinator {
    private let photoSource: any PhotoSyncSource
    private let reminderSource: any ReminderSyncSource
    private let notesSource: any NotesSyncSource
    private let imageConverter: any SyncImageConverting
    private let api: any SkylightSyncAPI
    private let stateStore: any SyncStatePersisting
    private let mealDateResolver: any MealDateResolving
    private let now: @Sendable () -> Date

    init(
        photoSource: any PhotoSyncSource,
        reminderSource: any ReminderSyncSource,
        notesSource: any NotesSyncSource,
        imageConverter: any SyncImageConverting,
        api: any SkylightSyncAPI,
        stateStore: any SyncStatePersisting,
        mealDateResolver: any MealDateResolving = DefaultMealDateResolver(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.photoSource = photoSource
        self.reminderSource = reminderSource
        self.notesSource = notesSource
        self.imageConverter = imageConverter
        self.api = api
        self.stateStore = stateStore
        self.mealDateResolver = mealDateResolver
        self.now = now
    }

    @MainActor
    static func live(
        apiClient: SkylightAPIClient,
        stateStore: SyncStateStore = SyncStateStore()
    ) -> SyncCoordinator {
        SyncCoordinator(
            photoSource: ApplePhotoLibrary(),
            reminderSource: AppleRemindersStore(),
            notesSource: AppleNotesStore(),
            imageConverter: ImageConversionService(),
            api: apiClient,
            stateStore: stateStore
        )
    }

    func sync(configuration: AppConfiguration) async throws -> SyncRunSummary {
        var summary = SyncRunSummary(dryRun: configuration.dryRun)
        guard configuration.hasEnabledSync else {
            return summary
        }

        let frameID = configuration.account.frameID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frameID.isEmpty else {
            throw SyncCoordinatorError.missingFrameID
        }

        var state = try await stateStore.loadSyncState()
        summary.photos = try await syncPhotos(
            mappings: configuration.photoMappings.filter(\.enabled),
            frameID: frameID,
            dryRun: configuration.dryRun,
            state: &state
        )
        try await checkpoint(state, dryRun: configuration.dryRun)
        summary.reminders = try await syncReminders(
            mappings: configuration.reminderMappings.filter(\.enabled),
            frameID: frameID,
            dryRun: configuration.dryRun,
            state: &state
        )
        try await checkpoint(state, dryRun: configuration.dryRun)
        summary.recipes = try await syncRecipes(
            selection: configuration.recipeSelection,
            frameID: frameID,
            dryRun: configuration.dryRun,
            state: &state
        )
        try await checkpoint(state, dryRun: configuration.dryRun)
        summary.meals = try await syncMeals(
            selection: configuration.mealSelection,
            frameID: frameID,
            dryRun: configuration.dryRun,
            state: &state
        )
        try await checkpoint(state, dryRun: configuration.dryRun)
        return summary
    }

    struct PhotoMappingPurge: Sendable {
        var photos = 0
        var albums = 0
    }

    /// Removes every bridge-managed Skylight photo for a mapping, then deletes any
    /// album the bridge created for it once that album is empty, and forgets its
    /// records. Apple Photos is never touched, so this is the only place the
    /// bridge's copies live. A bridge-created album that still holds photos the
    /// user added on Skylight is left in place. Best-effort per item: an
    /// already-deleted remote object does not abort the rest of the cleanup.
    @discardableResult
    func purgePhotoMapping(mappingID: UUID, frameID: String) async throws -> PhotoMappingPurge {
        var state = try await stateStore.loadSyncState()
        var result = PhotoMappingPurge()

        let records = state.photos
            .filter { $0.mappingID == mappingID && $0.frameID == frameID }
            .sorted { $0.appleAssetID < $1.appleAssetID }
        for record in records {
            if !record.skylightAlbumIDs.isEmpty {
                try? await api.removeMessages(
                    frameID: frameID,
                    albumIDs: record.skylightAlbumIDs.sorted(),
                    messageIDs: [record.skylightMessageID]
                )
            }
            try? await api.deleteMessage(frameID: frameID, messageID: record.skylightMessageID)
            state.photos.removeAll { $0.id == record.id }
            try await stateStore.saveSyncState(state)
            result.photos += 1
        }

        let albumRecords = state.photoAlbums
            .filter { $0.mappingID == mappingID && $0.frameID == frameID }
            .sorted { $0.albumID < $1.albumID }
        for albumRecord in albumRecords {
            // "Failed to list" must not read as "empty": deleting on a transport
            // error could destroy an album holding photos the user added on
            // Skylight. Keep the record so a later purge can retry.
            guard let remaining = try? await api.listAllAlbumMessageIDs(
                frameID: frameID,
                albumID: albumRecord.albumID
            ) else { continue }
            if remaining.isEmpty {
                try? await api.deleteAlbum(frameID: frameID, albumID: albumRecord.albumID)
                result.albums += 1
            }
            state.photoAlbums.removeAll { $0.id == albumRecord.id }
            try await stateStore.saveSyncState(state)
        }

        return result
    }

    /// Removes the linked items for a reminder mapping from the chosen side, then
    /// forgets its records. Because a mapping can be two-way, the caller decides
    /// whether to clear the Skylight list, Apple Reminders, or neither.
    func purgeReminderMapping(
        mappingID: UUID,
        frameID: String,
        side: ReminderMappingCleanupSide
    ) async throws -> Int {
        var state = try await stateStore.loadSyncState()
        let records = state.reminders
            .filter { $0.mappingID == mappingID && $0.frameID == frameID }
            .sorted { $0.appleReminderID < $1.appleReminderID }
        var affected = 0
        for record in records {
            switch side {
            case .skylight:
                try? await api.deleteListItem(
                    frameID: frameID,
                    listID: record.skylightListID,
                    itemID: record.skylightItemID
                )
                affected += 1
            case .appleReminders:
                try? await reminderSource.syncRemoveReminder(withID: record.appleReminderID)
                affected += 1
            case .none:
                break
            }
            state.reminders.removeAll { $0.id == record.id }
            try await stateStore.saveSyncState(state)
        }
        return affected
    }

    private func syncPhotos(
        mappings: [PhotoMapping],
        frameID: String,
        dryRun: Bool,
        state: inout SyncState
    ) async throws -> SyncDomainSummary {
        let maximumAssetsPerMapping = 5_000
        var summary = SyncDomainSummary()

        for mapping in mappings {
            let sourceAssets = try await photoAssets(for: mapping)
                .filter { $0.mediaKind == .image || $0.mediaKind == .livePhoto }
            guard sourceAssets.count <= maximumAssetsPerMapping else {
                throw SyncCoordinatorError.photoCollectionTooLarge(
                    count: sourceAssets.count,
                    maximum: maximumAssetsPerMapping
                )
            }

            let mappingRecords = state.photos.filter {
                $0.mappingID == mapping.id && $0.frameID == frameID
            }
            let currentAssetIDs = Set(sourceAssets.map(\.id))
            let needsDestination = !currentAssetIDs.isEmpty
            let destination = try await resolvePhotoDestination(
                mapping: mapping,
                frameID: frameID,
                dryRun: dryRun,
                needed: needsDestination
            )
            if destination.needsCreation {
                summary.planned += 1
                if !dryRun {
                    summary.applied += 1
                    if let albumID = destination.id {
                        recordManagedAlbum(
                            mappingID: mapping.id,
                            frameID: frameID,
                            albumID: albumID,
                            in: &state
                        )
                        try await checkpoint(state, dryRun: dryRun)
                    }
                }
            }

            for asset in sourceAssets.sorted(by: { $0.id < $1.id }) {
                let destinationID = destination.id
                    ?? (dryRun && destination.needsCreation
                        ? "dry-run-new-album:\(mapping.id.uuidString)"
                        : nil)
                guard let destinationID else {
                    throw SyncCoordinatorError.missingPhotoDestination(mapping.id)
                }
                let rendered = try await photoSource.syncRenderedPhoto(
                    withID: asset.id,
                    maximumLongEdge: mapping.maximumLongEdge
                )
                let converted = try await imageConverter.syncConvert(
                    rendered,
                    options: AppleImageConversionOptions(
                        maximumLongEdge: mapping.maximumLongEdge,
                        jpegQuality: mapping.jpegQuality
                    )
                )
                let existing = mappingRecords.first { $0.appleAssetID == asset.id }

                if let existing, existing.renderedHash == converted.sha256 {
                    let oldAlbumIDs = existing.skylightAlbumIDs.subtracting([destinationID])
                    let needsAdd = !existing.skylightAlbumIDs.contains(destinationID)
                    summary.planned += (needsAdd ? 1 : 0) + (oldAlbumIDs.isEmpty ? 0 : 1)
                    guard !dryRun, needsAdd || !oldAlbumIDs.isEmpty else { continue }
                    if needsAdd {
                        try await api.addMessages(
                            frameID: frameID,
                            albumIDs: [destinationID],
                            messageIDs: [existing.skylightMessageID]
                        )
                        summary.applied += 1
                    }
                    if !oldAlbumIDs.isEmpty {
                        try await api.removeMessages(
                            frameID: frameID,
                            albumIDs: oldAlbumIDs.sorted(),
                            messageIDs: [existing.skylightMessageID]
                        )
                        summary.applied += 1
                    }
                    upsertPhotoRecord(PhotoSyncRecord(
                        mappingID: mapping.id,
                        frameID: frameID,
                        destinationAlbumID: destinationID,
                        appleAssetID: asset.id,
                        renderedHash: existing.renderedHash,
                        skylightMessageID: existing.skylightMessageID,
                        skylightAlbumIDs: [destinationID],
                        lastSyncedAt: now()
                    ), in: &state)
                    try await checkpoint(state, dryRun: dryRun)
                    continue
                }

                summary.planned += 1
                if !dryRun {
                    let newMessageID = try await uploadPhoto(
                        converted,
                        frameID: frameID,
                        destinationAlbumID: destinationID
                    )
                    upsertPhotoRecord(
                        PhotoSyncRecord(
                            mappingID: mapping.id,
                            frameID: frameID,
                            destinationAlbumID: destinationID,
                            appleAssetID: asset.id,
                            renderedHash: converted.sha256,
                            skylightMessageID: newMessageID,
                            skylightAlbumIDs: [destinationID],
                            lastSyncedAt: now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)
                    if let previous = existing {
                        if !previous.skylightAlbumIDs.isEmpty {
                            try await api.removeMessages(
                                frameID: frameID,
                                albumIDs: previous.skylightAlbumIDs.sorted(),
                                messageIDs: [previous.skylightMessageID]
                            )
                        }
                        try await api.deleteMessage(
                            frameID: frameID,
                            messageID: previous.skylightMessageID
                        )
                    }
                    summary.applied += 1
                }
            }

            guard mapping.removalPolicy == .removeFromSkylight else { continue }
            let removedRecords = mappingRecords.filter {
                !currentAssetIDs.contains($0.appleAssetID)
            }
            summary.planned += removedRecords.count
            guard !dryRun else { continue }
            for record in removedRecords {
                    if !record.skylightAlbumIDs.isEmpty {
                        try await api.removeMessages(
                            frameID: frameID,
                            albumIDs: record.skylightAlbumIDs.sorted(),
                            messageIDs: [record.skylightMessageID]
                        )
                    }
                    try await api.deleteMessage(
                        frameID: frameID,
                        messageID: record.skylightMessageID
                    )
                    state.photos.removeAll { $0.id == record.id }
                    try await checkpoint(state, dryRun: dryRun)
                    summary.applied += 1
            }
        }
        return summary
    }

    private func photoAssets(for mapping: PhotoMapping) async throws -> [ApplePhotoAssetSnapshot] {
        switch mapping.sourceKind {
        case .album:
            guard let collectionID = mapping.sourceCollectionID, !collectionID.isEmpty else {
                throw SyncCoordinatorError.missingPhotoCollection(mapping.id)
            }
            return try await photoSource.syncPhotoAssets(in: collectionID)

        case .favorites:
            if let collectionID = mapping.sourceCollectionID, !collectionID.isEmpty {
                return try await photoSource.syncPhotoAssets(in: collectionID)
            }
            let collections = try await photoSource.syncPhotoCollections()
            guard let favorites = collections.first(where: { $0.kind == .favorites }) else {
                throw SyncCoordinatorError.missingPhotoCollection(mapping.id)
            }
            return try await photoSource.syncPhotoAssets(in: favorites.id)

        case .selectedPhotos:
            return try await photoSource.syncPhotoAssets(withIDs: mapping.selectedAssetIDs.sorted())
        }
    }

    private func resolvePhotoDestination(
        mapping: PhotoMapping,
        frameID: String,
        dryRun: Bool,
        needed: Bool
    ) async throws -> PhotoDestinationResolution {
        guard needed else {
            return PhotoDestinationResolution(id: mapping.destinationAlbumID, needsCreation: false)
        }
        let albums = try await api.listAlbums(frameID: frameID)
        if let albumID = mapping.destinationAlbumID, !albumID.isEmpty {
            guard albums.contains(where: { $0.id == albumID }) else {
                throw SyncCoordinatorError.invalidPhotoDestination(mapping.id)
            }
            return PhotoDestinationResolution(id: albumID, needsCreation: false)
        }

        let title = mapping.destinationAlbumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw SyncCoordinatorError.missingPhotoDestination(mapping.id)
        }
        let matches = albums.filter {
            $0.attributes.title?.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw SyncCoordinatorError.ambiguousPhotoDestination(title)
        }
        if let existing = matches.first {
            return PhotoDestinationResolution(id: existing.id, needsCreation: false)
        }
        guard !dryRun else {
            return PhotoDestinationResolution(id: nil, needsCreation: true)
        }
        let created = try await api.createAlbum(frameID: frameID, title: title)
        return PhotoDestinationResolution(id: created.id, needsCreation: true)
    }

    private func uploadPhoto(
        _ image: AppleConvertedImage,
        frameID: String,
        destinationAlbumID: String
    ) async throws -> String {
        guard image.data.count <= 26_214_400 else {
            throw SyncCoordinatorError.convertedImageTooLarge(
                assetID: image.assetID,
                bytes: image.data.count
            )
        }
        let upload = try await api.requestUploadURL(
            ext: "jpg",
            frameIDs: [frameID],
            caption: nil
        )
        let uploadURL: URL
        do {
            uploadURL = try SkylightAPIClient.validatedUploadURL(upload.url)
        } catch {
            throw SyncCoordinatorError.invalidUploadURL
        }
        guard let messageID = upload.messageIDs?.first else {
            throw SyncCoordinatorError.missingUploadMessageID
        }

        try await api.upload(data: image.data, to: uploadURL, contentType: "image/jpeg")
        try await waitForUploadedMessage(frameID: frameID, messageID: messageID)
        try await api.addMessages(
            frameID: frameID,
            albumIDs: [destinationAlbumID],
            messageIDs: [messageID]
        )
        return messageID
    }

    private func waitForUploadedMessage(frameID: String, messageID: String) async throws {
        for _ in 0..<40 {
            if let response = try? await api.listMessages(
                frameID: frameID,
                page: nil,
                syncToken: nil,
                pageToken: "__START__"
            ), let message = response.data.first(where: { $0.id == messageID }) {
                switch message.attributes.status {
                case "awaiting_download", "downloaded":
                    return
                case "invalid_asset_type":
                    throw SyncCoordinatorError.photoProcessingFailed(
                        messageID: messageID,
                        status: "invalid asset type"
                    )
                default:
                    break
                }
            }
            try await ContinuousClock().sleep(for: .milliseconds(500))
        }
        throw SyncCoordinatorError.photoProcessingTimedOut(messageID)
    }

    private func syncReminders(
        mappings: [ReminderListMapping],
        frameID: String,
        dryRun: Bool,
        state: inout SyncState
    ) async throws -> SyncDomainSummary {
        var summary = SyncDomainSummary()

        for mapping in mappings {
            let allApple = try await reminderSource.syncReminders(in: mapping.sourceListID)
            let selectedApple = mapping.selectionMode == .everything
                ? allApple
                : allApple.filter { mapping.selectedReminderIDs.contains($0.id) }
            let destination = try await resolveReminderDestination(
                mapping: mapping,
                frameID: frameID,
                dryRun: dryRun
            )
            if destination.needsCreation {
                summary.planned += 1
                if !dryRun { summary.applied += 1 }
            }
            let records = state.reminders.filter {
                $0.mappingID == mapping.id &&
                    $0.frameID == frameID &&
                    (destination.id == nil || $0.skylightListID == destination.id)
            }
            let remoteResources: [SkylightResource<SkylightListItemAttributes>] = if let destinationID = destination.id {
                try await api.listListItems(frameID: frameID, listID: destinationID)
            } else {
                []
            }
            let allowedRemoteIDs = Set(records.map(\.skylightItemID))
            let selectedRemoteResources = mapping.selectionMode == .everything
                ? remoteResources
                : remoteResources.filter { allowedRemoteIDs.contains($0.id) }
            let syncTime = now()

            let appleSnapshots = selectedApple.map {
                ReminderSnapshot(
                    id: $0.id,
                    title: $0.title,
                    notes: nil,
                    isCompleted: $0.isCompleted,
                    modifiedAt: $0.modificationDate ?? $0.creationDate ?? .distantPast
                )
            }
            let remoteSnapshots = selectedRemoteResources.map { resource in
                let contentFingerprint = reminderFingerprint(
                    title: resource.attributes.label ?? "",
                    isCompleted: resource.attributes.status == .completed
                )
                let record = records.first { $0.skylightItemID == resource.id }
                let modifiedAt: Date
                if let record, record.contentFingerprint == contentFingerprint {
                    modifiedAt = record.lastSkylightModifiedAt
                } else {
                    modifiedAt = syncTime
                }
                return SkylightListItemSnapshot(
                    id: resource.id,
                    title: resource.attributes.label ?? "",
                    notes: nil,
                    isCompleted: resource.attributes.status == .completed,
                    modifiedAt: modifiedAt
                )
            }
            var activeRecords = records
            if let destinationID = destination.id {
                let pairs = ReminderSyncPlanner.adoptionPairs(
                    apple: appleSnapshots,
                    skylight: remoteSnapshots,
                    links: activeRecords.map(Self.link(for:))
                )
                let appleForAdoption = selectedApple.firstByID
                let remoteForAdoption = remoteSnapshots.firstByID
                for pair in pairs {
                    guard let apple = appleForAdoption[pair.appleID],
                          let remote = remoteForAdoption[pair.skylightID] else { continue }
                    let adopted = ReminderSyncRecord(
                        mappingID: mapping.id,
                        frameID: frameID,
                        skylightListID: destinationID,
                        appleReminderID: apple.id,
                        appleExternalID: apple.externalID,
                        skylightItemID: remote.id,
                        lastAppleModifiedAt: apple.modificationDate ?? apple.creationDate ?? .distantPast,
                        lastSkylightModifiedAt: remote.modifiedAt,
                        contentFingerprint: reminderFingerprint(
                            title: apple.title,
                            isCompleted: apple.isCompleted
                        ),
                        lastSyncedTitle: apple.title,
                        lastSyncedCompleted: apple.isCompleted
                    )
                    upsertReminderRecord(adopted, in: &state)
                    activeRecords.removeAll {
                        $0.appleReminderID == adopted.appleReminderID ||
                            $0.skylightItemID == adopted.skylightItemID
                    }
                    activeRecords.append(adopted)
                }
                if !pairs.isEmpty {
                    try await checkpoint(state, dryRun: dryRun)
                }
            }

            let links = activeRecords.map(Self.link(for:))
            let actions = ReminderSyncPlanner.plan(
                apple: appleSnapshots,
                skylight: remoteSnapshots,
                links: links,
                direction: mapping.direction,
                conflictPolicy: mapping.conflictPolicy
            )
            summary.planned += actions.count
            guard !dryRun else { continue }
            guard let destinationID = destination.id else {
                throw SyncCoordinatorError.missingReminderDestination(mapping.id)
            }

            let appleByID = selectedApple.firstByID
            let remoteByID = selectedRemoteResources.firstByID
            let remoteSnapshotByID = remoteSnapshots.firstByID

            for action in actions {
                switch action {
                case let .createRemote(appleID):
                    guard let apple = appleByID[appleID] else { continue }
                    let remote = try await api.createListItem(
                        frameID: frameID,
                        listID: destinationID,
                        request: listItemRequest(for: apple)
                    )
                    upsertReminderRecord(
                        reminderRecord(
                            mapping: mapping,
                            frameID: frameID,
                            listID: destinationID,
                            apple: apple,
                            remoteID: remote.id,
                            remoteModifiedAt: now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)

                case let .createApple(remoteID):
                    guard let remote = remoteByID[remoteID] else { continue }
                    let apple = try await reminderSource.syncCreateReminder(
                        in: mapping.sourceListID,
                        draft: AppleReminderDraft(
                            title: nonemptyTitle(remote.attributes.label),
                            isCompleted: remote.attributes.status == .completed
                        )
                    )
                    upsertReminderRecord(
                        reminderRecord(
                            mapping: mapping,
                            frameID: frameID,
                            listID: destinationID,
                            apple: apple,
                            remoteID: remoteID,
                            remoteModifiedAt: remoteSnapshotByID[remoteID]?.modifiedAt ?? now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)

                case let .updateRemote(appleID, remoteID):
                    guard let apple = appleByID[appleID] else { continue }
                    _ = try await api.updateListItem(
                        frameID: frameID,
                        listID: destinationID,
                        itemID: remoteID,
                        request: listItemRequest(for: apple)
                    )
                    upsertReminderRecord(
                        reminderRecord(
                            mapping: mapping,
                            frameID: frameID,
                            listID: destinationID,
                            apple: apple,
                            remoteID: remoteID,
                            remoteModifiedAt: now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)

                case let .updateApple(appleID, remoteID):
                    guard let remote = remoteByID[remoteID] else { continue }
                    let apple = try await reminderSource.syncUpdateReminder(
                        withID: appleID,
                        patch: AppleReminderPatch(
                            title: nonemptyTitle(remote.attributes.label),
                            isCompleted: remote.attributes.status == .completed
                        )
                    )
                    upsertReminderRecord(
                        reminderRecord(
                            mapping: mapping,
                            frameID: frameID,
                            listID: destinationID,
                            apple: apple,
                            remoteID: remoteID,
                            remoteModifiedAt: remoteSnapshotByID[remoteID]?.modifiedAt ?? now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)

                case let .merge(appleID, remoteID, title, isCompleted):
                    guard appleByID[appleID] != nil else { continue }
                    let apple = try await reminderSource.syncUpdateReminder(
                        withID: appleID,
                        patch: AppleReminderPatch(title: title, isCompleted: isCompleted)
                    )
                    _ = try await api.updateListItem(
                        frameID: frameID,
                        listID: destinationID,
                        itemID: remoteID,
                        request: SkylightListItemRequest(
                            label: title,
                            status: isCompleted ? .completed : .pending
                        )
                    )
                    upsertReminderRecord(
                        reminderRecord(
                            mapping: mapping,
                            frameID: frameID,
                            listID: destinationID,
                            apple: apple,
                            remoteID: remoteID,
                            remoteModifiedAt: now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)

                case let .deleteRemote(remoteID):
                    try await api.deleteListItem(
                        frameID: frameID,
                        listID: destinationID,
                        itemID: remoteID
                    )
                    state.reminders.removeAll {
                        $0.mappingID == mapping.id &&
                            $0.frameID == frameID &&
                            $0.skylightListID == destinationID &&
                            $0.skylightItemID == remoteID
                    }
                    try await checkpoint(state, dryRun: dryRun)

                case let .deleteApple(appleID):
                    if appleByID[appleID]?.hasRecurrenceRules == true {
                        state.reminders.removeAll {
                            $0.mappingID == mapping.id &&
                                $0.frameID == frameID &&
                                $0.skylightListID == destinationID &&
                                $0.appleReminderID == appleID
                        }
                        try await checkpoint(state, dryRun: dryRun)
                        continue
                    }
                    try await reminderSource.syncRemoveReminder(withID: appleID)
                    state.reminders.removeAll {
                        $0.mappingID == mapping.id &&
                            $0.frameID == frameID &&
                            $0.skylightListID == destinationID &&
                            $0.appleReminderID == appleID
                    }
                    try await checkpoint(state, dryRun: dryRun)
                }
                summary.applied += 1
            }
        }
        return summary
    }

    private func resolveReminderDestination(
        mapping: ReminderListMapping,
        frameID: String,
        dryRun: Bool
    ) async throws -> ReminderDestinationResolution {
        let lists = try await api.listLists(frameID: frameID).data
        let configuredID = mapping.destinationListID.trimmed
        if !configuredID.isEmpty {
            guard lists.contains(where: { $0.id == configuredID }) else {
                throw SyncCoordinatorError.invalidReminderDestination(mapping.id)
            }
            return ReminderDestinationResolution(id: configuredID, needsCreation: false)
        }
        let title = mapping.destinationListTitle.trimmed
        guard !title.isEmpty else {
            throw SyncCoordinatorError.missingReminderDestination(mapping.id)
        }
        let matches = lists.filter {
            $0.attributes.label?.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw SyncCoordinatorError.ambiguousReminderDestination(title)
        }
        if let existing = matches.first {
            return ReminderDestinationResolution(id: existing.id, needsCreation: false)
        }
        guard !dryRun else {
            return ReminderDestinationResolution(id: nil, needsCreation: true)
        }
        let created = try await api.createList(
            frameID: frameID,
            request: SkylightListRequest(label: title, kind: mapping.destinationKind)
        )
        return ReminderDestinationResolution(id: created.id, needsCreation: true)
    }

    private struct ParsedRecipeNote {
        let note: AppleNoteSnapshot
        let draft: RecipeDraft
        let contentHash: String
        let hasAttachments: Bool
    }

    private func syncRecipes(
        selection: NotesSelection,
        frameID: String,
        dryRun: Bool,
        state: inout SyncState
    ) async throws -> SyncDomainSummary {
        guard selection.enabled else { return SyncDomainSummary() }
        guard let folderID = selection.folderID else {
            throw SyncCoordinatorError.missingNotesFolder(selection.kind)
        }
        let twoWay = selection.direction == .twoWay
        let noteSummaries = try await selectedNoteSummaries(for: selection)
            .filter { !$0.isPasswordProtected }
            .sorted { $0.id < $1.id }
        let mealCategoryID = try await resolveMealCategoryID(
            selection: selection,
            frameID: frameID,
            needed: !noteSummaries.isEmpty
        )
        var summary = SyncDomainSummary()

        var parsedNotes: [ParsedRecipeNote] = []
        for noteSummary in noteSummaries {
            let note = try await notesSource.syncNote(
                withID: noteSummary.id,
                inFolderID: folderID
            )
            do {
                parsedNotes.append(ParsedRecipeNote(
                    note: note,
                    draft: try RecipeParser.parse(note.plaintext),
                    contentHash: stableHash(note.plaintext),
                    hasAttachments: noteSummary.attachmentCount > 0
                ))
            } catch RecipeParserError.emptyNote {
                // A blank note cannot become a recipe; leave it alone.
            }
        }

        let remoteRecipes = twoWay
            ? (try await api.listRecipes(frameID: frameID)).sorted(by: { $0.id < $1.id })
            : []
        let remoteByID = remoteRecipes.firstByID

        var adoptedNoteIDs: Set<String> = []
        var adoptedRemoteIDs: Set<String> = []
        if twoWay {
            try await adoptRecipes(
                parsedNotes: parsedNotes,
                remoteRecipes: remoteRecipes,
                conflictPolicy: selection.conflictPolicy,
                frameID: frameID,
                folderID: folderID,
                mealCategoryID: mealCategoryID,
                formattedNotes: selection.formattedNotes,
                dryRun: dryRun,
                adoptedNoteIDs: &adoptedNoteIDs,
                adoptedRemoteIDs: &adoptedRemoteIDs,
                summary: &summary,
                state: &state
            )
        }

        var trashedNoteIDs: Set<String> = []
        try await reconcileLinkedRecipes(
            parsedNotes: parsedNotes,
            remoteByID: remoteByID,
            twoWay: twoWay,
            conflictPolicy: selection.conflictPolicy,
            frameID: frameID,
            folderID: folderID,
            mealCategoryID: mealCategoryID,
            formattedNotes: selection.formattedNotes,
            dryRun: dryRun,
            trashedNoteIDs: &trashedNoteIDs,
            summary: &summary,
            state: &state
        )

        var createdNoteIDs: Set<String> = []
        if twoWay, selection.selectionMode == .everything {
            try await pullNewRecipes(
                remoteRecipes: remoteRecipes,
                adoptedRemoteIDs: adoptedRemoteIDs,
                frameID: frameID,
                folderID: folderID,
                formattedNotes: selection.formattedNotes,
                dryRun: dryRun,
                createdNoteIDs: &createdNoteIDs,
                summary: &summary,
                state: &state
            )
        }

        for parsed in parsedNotes {
            guard !adoptedNoteIDs.contains(parsed.note.id),
                  !trashedNoteIDs.contains(parsed.note.id),
                  recipeRecord(forNote: parsed.note.id, frameID: frameID, in: state) == nil else {
                continue
            }
            summary.planned += 1
            guard !dryRun else { continue }
            let remote = try await api.createRecipe(
                frameID: frameID,
                request: recipeRequest(for: parsed.draft, categoryID: mealCategoryID)
            )
            upsertNoteRecord(
                makeRecipeRecord(
                    noteID: parsed.note.id,
                    frameID: frameID,
                    contentHash: parsed.contentHash,
                    skylightID: remote.id,
                    noteModifiedAt: parsed.note.modificationDate,
                    remoteUpdatedAt: remote.attributes.updatedAt
                ),
                in: &state
            )
            try await checkpoint(state, dryRun: dryRun)
            summary.applied += 1
        }

        let desiredNoteIDs = Set(try await selectedNoteSummaries(for: selection).map(\.id))
            .union(createdNoteIDs)
        let removedRecords = state.notes
            .filter {
                $0.kind == .recipes &&
                    $0.frameID == frameID &&
                    !desiredNoteIDs.contains($0.appleNoteID)
            }
            .sorted { $0.appleNoteID < $1.appleNoteID }
        summary.planned += removedRecords.count
        if !dryRun {
            for record in removedRecords {
                try await api.deleteRecipe(
                    frameID: frameID,
                    recipeID: record.skylightID,
                    applyToSittings: false
                )
                state.notes.removeAll { $0.id == record.id }
                try await checkpoint(state, dryRun: dryRun)
                summary.applied += 1
            }
        }
        return summary
    }

    /// Pairs unlinked notes with unlinked Skylight recipes that share a title, so
    /// linking a folder to an existing recipe box never duplicates content. Pairs
    /// whose content already matches become silent links; diverging pairs count as
    /// one planned change resolved by the conflict policy.
    private func adoptRecipes(
        parsedNotes: [ParsedRecipeNote],
        remoteRecipes: [SkylightResource<SkylightRecipeAttributes>],
        conflictPolicy: SyncConflictPolicy,
        frameID: String,
        folderID: String,
        mealCategoryID: String?,
        formattedNotes: Bool,
        dryRun: Bool,
        adoptedNoteIDs: inout Set<String>,
        adoptedRemoteIDs: inout Set<String>,
        summary: inout SyncDomainSummary,
        state: inout SyncState
    ) async throws {
        let linkedRemoteIDs = Set(
            state.notes
                .filter { $0.kind == .recipes && $0.frameID == frameID }
                .map(\.skylightID)
        )
        var candidates = remoteRecipes.filter { !linkedRemoteIDs.contains($0.id) }

        for parsed in parsedNotes
        where recipeRecord(forNote: parsed.note.id, frameID: frameID, in: state) == nil {
            let key = parsed.draft.title.trimmed.lowercased()
            guard let index = candidates.firstIndex(where: {
                ($0.attributes.summary ?? "").trimmed.lowercased() == key
            }) else { continue }
            let remote = candidates.remove(at: index)
            adoptedNoteIDs.insert(parsed.note.id)
            adoptedRemoteIDs.insert(remote.id)

            let remoteDraft = RecipeNoteFormatter.draft(from: remote.attributes)
            if remoteDraft == parsed.draft {
                upsertNoteRecord(
                    makeRecipeRecord(
                        noteID: parsed.note.id,
                        frameID: frameID,
                        contentHash: parsed.contentHash,
                        skylightID: remote.id,
                        noteModifiedAt: parsed.note.modificationDate,
                        remoteUpdatedAt: remote.attributes.updatedAt
                    ),
                    in: &state
                )
                try await checkpoint(state, dryRun: dryRun)
                continue
            }

            summary.planned += 1
            guard !dryRun else { continue }
            // A note with attachments is never rewritten: updating a note body
            // through automation can wipe its attachments.
            if parsed.hasAttachments || appleWinsConflict(
                policy: conflictPolicy,
                noteModifiedAt: parsed.note.modificationDate,
                remoteUpdatedAt: remote.attributes.updatedAt
            ) {
                try await pushRecipeUpdate(
                    parsed: parsed,
                    recipeID: remote.id,
                    frameID: frameID,
                    mealCategoryID: mealCategoryID,
                    state: &state
                )
            } else {
                try await applyRemoteRecipe(
                    remote,
                    toNoteID: parsed.note.id,
                    frameID: frameID,
                    folderID: folderID,
                    formattedNotes: formattedNotes,
                    state: &state
                )
            }
            summary.applied += 1
        }
    }

    private func reconcileLinkedRecipes(
        parsedNotes: [ParsedRecipeNote],
        remoteByID: [String: SkylightResource<SkylightRecipeAttributes>],
        twoWay: Bool,
        conflictPolicy: SyncConflictPolicy,
        frameID: String,
        folderID: String,
        mealCategoryID: String?,
        formattedNotes: Bool,
        dryRun: Bool,
        trashedNoteIDs: inout Set<String>,
        summary: inout SyncDomainSummary,
        state: inout SyncState
    ) async throws {
        for parsed in parsedNotes {
            guard let record = recipeRecord(
                forNote: parsed.note.id,
                frameID: frameID,
                in: state
            ) else { continue }

            let remote = remoteByID[record.skylightID]
            if twoWay, remote == nil {
                // The linked recipe was deleted on Skylight. Retire the note to
                // Recently Deleted so the deletion flows back to Apple Notes.
                summary.planned += 1
                guard !dryRun else { continue }
                try await notesSource.syncTrashNote(
                    withID: parsed.note.id,
                    inFolderID: folderID
                )
                trashedNoteIDs.insert(parsed.note.id)
                state.notes.removeAll { $0.id == record.id }
                try await checkpoint(state, dryRun: dryRun)
                summary.applied += 1
                continue
            }

            let appleChanged = parsed.contentHash != record.contentHash
            var remoteChanged = false
            if twoWay, let remote {
                if let lastSeen = record.lastSkylightUpdatedAt {
                    remoteChanged = (remote.attributes.updatedAt ?? "") != lastSeen
                } else {
                    // Records written before two-way sync have no remote clock.
                    // Seed it now instead of treating history as a fresh change.
                    var seeded = record
                    seeded.lastSkylightUpdatedAt = remote.attributes.updatedAt ?? ""
                    seeded.lastAppleModifiedAt = parsed.note.modificationDate
                    upsertNoteRecord(seeded, in: &state)
                    try await checkpoint(state, dryRun: dryRun)
                }
            }

            switch (appleChanged, remoteChanged, remote) {
            case (false, false, _):
                continue
            case (true, false, _):
                summary.planned += 1
                guard !dryRun else { continue }
                try await pushRecipeUpdate(
                    parsed: parsed,
                    recipeID: record.skylightID,
                    frameID: frameID,
                    mealCategoryID: mealCategoryID,
                    state: &state
                )
                summary.applied += 1
            case let (false, true, .some(remote)):
                if parsed.hasAttachments {
                    // Rewriting a note through automation can wipe attachments,
                    // so acknowledge the remote revision and keep the note as
                    // the Apple-authoritative copy.
                    guard !dryRun else { continue }
                    var acknowledged = record
                    acknowledged.lastSkylightUpdatedAt = remote.attributes.updatedAt ?? ""
                    upsertNoteRecord(acknowledged, in: &state)
                    try await checkpoint(state, dryRun: dryRun)
                    continue
                }
                summary.planned += 1
                guard !dryRun else { continue }
                try await applyRemoteRecipe(
                    remote,
                    toNoteID: parsed.note.id,
                    frameID: frameID,
                    folderID: folderID,
                    formattedNotes: formattedNotes,
                    state: &state
                )
                summary.applied += 1
            case let (true, true, .some(remote)):
                summary.planned += 1
                guard !dryRun else { continue }
                if parsed.hasAttachments || appleWinsConflict(
                    policy: conflictPolicy,
                    noteModifiedAt: parsed.note.modificationDate,
                    remoteUpdatedAt: remote.attributes.updatedAt
                ) {
                    try await pushRecipeUpdate(
                        parsed: parsed,
                        recipeID: record.skylightID,
                        frameID: frameID,
                        mealCategoryID: mealCategoryID,
                        state: &state
                    )
                } else {
                    try await applyRemoteRecipe(
                        remote,
                        toNoteID: parsed.note.id,
                        frameID: frameID,
                        folderID: folderID,
                        formattedNotes: formattedNotes,
                        state: &state
                    )
                }
                summary.applied += 1
            case (_, true, .none):
                continue
            }
        }
    }

    private func pullNewRecipes(
        remoteRecipes: [SkylightResource<SkylightRecipeAttributes>],
        adoptedRemoteIDs: Set<String>,
        frameID: String,
        folderID: String,
        formattedNotes: Bool,
        dryRun: Bool,
        createdNoteIDs: inout Set<String>,
        summary: inout SyncDomainSummary,
        state: inout SyncState
    ) async throws {
        let linkedRemoteIDs = Set(
            state.notes
                .filter { $0.kind == .recipes && $0.frameID == frameID }
                .map(\.skylightID)
        )
        for remote in remoteRecipes
        where !linkedRemoteIDs.contains(remote.id) && !adoptedRemoteIDs.contains(remote.id) {
            summary.planned += 1
            guard !dryRun else { continue }
            let draft = RecipeNoteFormatter.draft(from: remote.attributes)
            let noteID = try await notesSource.syncCreateNote(
                inFolderID: folderID,
                bodyHTML: RecipeNoteFormatter.bodyHTML(for: draft, formatted: formattedNotes)
            )
            let readback = try await notesSource.syncNote(withID: noteID, inFolderID: folderID)
            upsertNoteRecord(
                makeRecipeRecord(
                    noteID: noteID,
                    frameID: frameID,
                    contentHash: stableHash(readback.plaintext),
                    skylightID: remote.id,
                    noteModifiedAt: readback.modificationDate,
                    remoteUpdatedAt: remote.attributes.updatedAt
                ),
                in: &state
            )
            createdNoteIDs.insert(noteID)
            try await checkpoint(state, dryRun: dryRun)
            summary.applied += 1
        }
    }

    private func pushRecipeUpdate(
        parsed: ParsedRecipeNote,
        recipeID: String,
        frameID: String,
        mealCategoryID: String?,
        state: inout SyncState
    ) async throws {
        let remote = try await api.updateRecipe(
            frameID: frameID,
            recipeID: recipeID,
            request: recipeRequest(for: parsed.draft, categoryID: mealCategoryID)
        )
        upsertNoteRecord(
            makeRecipeRecord(
                noteID: parsed.note.id,
                frameID: frameID,
                contentHash: parsed.contentHash,
                skylightID: remote.id,
                noteModifiedAt: parsed.note.modificationDate,
                remoteUpdatedAt: remote.attributes.updatedAt
            ),
            in: &state
        )
        try await checkpoint(state, dryRun: false)
    }

    private func applyRemoteRecipe(
        _ remote: SkylightResource<SkylightRecipeAttributes>,
        toNoteID noteID: String,
        frameID: String,
        folderID: String,
        formattedNotes: Bool,
        state: inout SyncState
    ) async throws {
        let draft = RecipeNoteFormatter.draft(from: remote.attributes)
        try await notesSource.syncUpdateNote(
            withID: noteID,
            inFolderID: folderID,
            bodyHTML: RecipeNoteFormatter.bodyHTML(for: draft, formatted: formattedNotes)
        )
        let readback = try await notesSource.syncNote(withID: noteID, inFolderID: folderID)
        upsertNoteRecord(
            makeRecipeRecord(
                noteID: noteID,
                frameID: frameID,
                contentHash: stableHash(readback.plaintext),
                skylightID: remote.id,
                noteModifiedAt: readback.modificationDate,
                remoteUpdatedAt: remote.attributes.updatedAt
            ),
            in: &state
        )
        try await checkpoint(state, dryRun: false)
    }

    private func recipeRecord(
        forNote noteID: String,
        frameID: String,
        in state: SyncState
    ) -> NoteSyncRecord? {
        state.notes.first {
            $0.kind == .recipes && $0.frameID == frameID && $0.appleNoteID == noteID
        }
    }

    private func makeRecipeRecord(
        noteID: String,
        frameID: String,
        contentHash: String,
        skylightID: String,
        noteModifiedAt: Date?,
        remoteUpdatedAt: String?
    ) -> NoteSyncRecord {
        NoteSyncRecord(
            kind: .recipes,
            frameID: frameID,
            appleNoteID: noteID,
            contentHash: contentHash,
            skylightID: skylightID,
            lastSyncedAt: now(),
            lastAppleModifiedAt: noteModifiedAt,
            lastSkylightUpdatedAt: remoteUpdatedAt
        )
    }

    private func appleWinsConflict(
        policy: SyncConflictPolicy,
        noteModifiedAt: Date?,
        remoteUpdatedAt: String?
    ) -> Bool {
        switch policy {
        case .appleWins:
            return true
        case .skylightWins:
            return false
        case .newestWins:
            let apple = noteModifiedAt ?? .distantPast
            let remote = Self.skylightDate(remoteUpdatedAt) ?? .distantPast
            // Ties keep Apple as the source of truth.
            return apple >= remote
        }
    }

    private static func skylightDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private func syncMeals(
        selection: NotesSelection,
        frameID: String,
        dryRun: Bool,
        state: inout SyncState
    ) async throws -> SyncDomainSummary {
        guard selection.enabled else { return SyncDomainSummary() }
        let notes = try await selectedNotes(for: selection)
        let mealCategoryID = try await resolveMealCategoryID(
            selection: selection,
            frameID: frameID,
            needed: !notes.isEmpty
        )
        let recipesByTitle = try await api.listRecipes(frameID: frameID).reduce(into: [String: String]()) {
            result, recipe in
            guard let title = recipe.attributes.summary?.trimmed, !title.isEmpty else { return }
            result[title.lowercased()] = recipe.id
        }
        var summary = SyncDomainSummary()

        for note in notes {
            var occurrences: [String: Int] = [:]
            for meal in try MealPlanParser.parse(note.plaintext) {
                let date = try mealDateResolver.resolveMealDate(meal.day, relativeTo: now())
                let slot = mealSlotKey(noteID: note.id, meal: meal, occurrences: &occurrences)
                let contentHash = stableHash(
                    [date, meal.category, meal.recipeTitle].joined(separator: "\u{0}")
                )
                let existing = state.notes.first {
                    $0.kind == .meals && $0.frameID == frameID && $0.appleNoteID == slot
                }
                guard existing?.contentHash != contentHash else { continue }
                let matchedRecipeID = recipesByTitle[meal.recipeTitle.trimmed.lowercased()]

                let createRequest = SkylightMealSittingRequest(
                    date: date,
                    summary: matchedRecipeID == nil ? meal.recipeTitle : nil,
                    description: matchedRecipeID == nil ? meal.category : nil,
                    note: "Imported from Apple Notes: \(note.title)",
                    mealRecipeID: matchedRecipeID,
                    mealCategoryID: mealCategoryID,
                    addToGroceryList: false
                )

                if let existing {
                    let reference = try MealRemoteReference.decode(existing.skylightID)
                    if reference.instanceISO == date {
                        summary.planned += 1
                        guard !dryRun else { continue }
                        _ = try await api.updateMealInstance(
                            frameID: frameID,
                            mealID: reference.mealID,
                            instanceISO: reference.instanceISO,
                            request: SkylightMealInstanceUpdateRequest(
                                summary: matchedRecipeID == nil ? meal.recipeTitle : nil,
                                description: matchedRecipeID == nil ? meal.category : nil,
                                note: "Imported from Apple Notes: \(note.title)",
                                mealRecipeID: matchedRecipeID,
                                mealCategoryID: mealCategoryID,
                                addToGroceryList: false
                            )
                        )
                        upsertNoteRecord(
                            NoteSyncRecord(
                                kind: .meals,
                                frameID: frameID,
                                appleNoteID: slot,
                                contentHash: contentHash,
                                skylightID: existing.skylightID,
                                lastSyncedAt: now()
                            ),
                            in: &state
                        )
                        try await checkpoint(state, dryRun: dryRun)
                        summary.applied += 1
                    } else {
                        summary.planned += 2
                        guard !dryRun else { continue }
                        let remote = try await api.createMealSitting(
                            frameID: frameID,
                            request: createRequest
                        )
                        let newReference = MealRemoteReference(
                            mealID: remote.id,
                            instanceISO: remote.attributes.date ?? date
                        )
                        upsertNoteRecord(
                            NoteSyncRecord(
                                kind: .meals,
                                frameID: frameID,
                                appleNoteID: slot,
                                contentHash: contentHash,
                                skylightID: try newReference.encoded(),
                                lastSyncedAt: now()
                            ),
                            in: &state
                        )
                        try await checkpoint(state, dryRun: dryRun)
                        try await api.deleteMealInstance(
                            frameID: frameID,
                            mealID: reference.mealID,
                            instanceISO: reference.instanceISO,
                            applyTo: nil
                        )
                        summary.applied += 2
                    }
                } else {
                    summary.planned += 1
                    guard !dryRun else { continue }
                    let remote = try await api.createMealSitting(
                        frameID: frameID,
                        request: createRequest
                    )
                    let reference = MealRemoteReference(
                        mealID: remote.id,
                        instanceISO: remote.attributes.date ?? date
                    )
                    upsertNoteRecord(
                        NoteSyncRecord(
                            kind: .meals,
                            frameID: frameID,
                            appleNoteID: slot,
                            contentHash: contentHash,
                            skylightID: try reference.encoded(),
                            lastSyncedAt: now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)
                    summary.applied += 1
                }
            }
        }

        let parsedSlots = try desiredMealSlots(notes: notes)
        let protectedNoteIDs = Set(
            try await selectedNoteSummaries(for: selection)
                .filter(\.isPasswordProtected)
                .map(\.id)
        )
        let removedRecords = state.notes.filter {
            guard $0.kind == .meals,
                  $0.frameID == frameID,
                  !parsedSlots.contains($0.appleNoteID) else { return false }
            let sourceNoteID = $0.appleNoteID.components(separatedBy: "::meal::").first ?? ""
            return !protectedNoteIDs.contains(sourceNoteID)
        }
        summary.planned += removedRecords.count
        if !dryRun {
            for record in removedRecords {
                let reference = try MealRemoteReference.decode(record.skylightID)
                try await api.deleteMealInstance(
                    frameID: frameID,
                    mealID: reference.mealID,
                    instanceISO: reference.instanceISO,
                    applyTo: nil
                )
                state.notes.removeAll { $0.id == record.id }
                try await checkpoint(state, dryRun: dryRun)
                summary.applied += 1
            }
        }
        return summary
    }

    private func desiredMealSlots(notes: [AppleNoteSnapshot]) throws -> Set<String> {
        var result: Set<String> = []
        for note in notes {
            var occurrences: [String: Int] = [:]
            for meal in try MealPlanParser.parse(note.plaintext) {
                result.insert(mealSlotKey(noteID: note.id, meal: meal, occurrences: &occurrences))
            }
        }
        return result
    }

    private func selectedNotes(for selection: NotesSelection) async throws -> [AppleNoteSnapshot] {
        let selected = try await selectedNoteSummaries(for: selection)
            .filter { !$0.isPasswordProtected }
        guard let folderID = selection.folderID else {
            throw SyncCoordinatorError.missingNotesFolder(selection.kind)
        }

        var notes: [AppleNoteSnapshot] = []
        for summary in selected.sorted(by: { $0.id < $1.id }) {
            notes.append(
                try await notesSource.syncNote(withID: summary.id, inFolderID: folderID)
            )
        }
        return notes
    }

    private func resolveMealCategoryID(
        selection: NotesSelection,
        frameID: String,
        needed: Bool
    ) async throws -> String? {
        guard needed else { return selection.destinationCategoryID }
        let categories = try await api.listMealCategories(frameID: frameID)
        if let configured = selection.destinationCategoryID?.trimmed, !configured.isEmpty {
            guard categories.contains(where: { $0.id == configured }) else {
                throw SyncCoordinatorError.invalidMealCategory(selection.kind)
            }
            return configured
        }
        guard let categoryID = categories.first?.id else {
            throw SyncCoordinatorError.missingMealCategory(selection.kind)
        }
        return categoryID
    }

    private func selectedNoteSummaries(
        for selection: NotesSelection
    ) async throws -> [AppleNoteSummarySnapshot] {
        guard let folderID = selection.folderID, !folderID.isEmpty else {
            throw SyncCoordinatorError.missingNotesFolder(selection.kind)
        }
        let summaries = try await notesSource.syncNoteSummaries(inFolderID: folderID)
        return selection.selectionMode == .everything
            ? summaries
            : summaries.filter { selection.selectedNoteIDs.contains($0.id) }
    }

    private func recipeRequest(
        for draft: RecipeDraft,
        categoryID: String?
    ) -> SkylightRecipeRequest {
        // The description uses the same grammar the note formatter writes and the
        // parser reads, so pulled recipes round-trip without spurious changes.
        SkylightRecipeRequest(
            mealCategoryID: categoryID,
            summary: draft.title,
            description: RecipeNoteFormatter.skylightDescription(for: draft),
            ingredients: draft.ingredients,
            url: draft.sourceURL
        )
    }

    private func listItemRequest(for reminder: AppleReminderSnapshot) -> SkylightListItemRequest {
        SkylightListItemRequest(
            label: reminder.title,
            status: reminder.isCompleted ? .completed : .pending
        )
    }

    private func reminderRecord(
        mapping: ReminderListMapping,
        frameID: String,
        listID: String,
        apple: AppleReminderSnapshot,
        remoteID: String,
        remoteModifiedAt: Date
    ) -> ReminderSyncRecord {
        ReminderSyncRecord(
            mappingID: mapping.id,
            frameID: frameID,
            skylightListID: listID,
            appleReminderID: apple.id,
            appleExternalID: apple.externalID,
            skylightItemID: remoteID,
            lastAppleModifiedAt: apple.modificationDate ?? apple.creationDate ?? .distantPast,
            lastSkylightModifiedAt: remoteModifiedAt,
            contentFingerprint: reminderFingerprint(
                title: apple.title,
                isCompleted: apple.isCompleted
            ),
            lastSyncedTitle: apple.title,
            lastSyncedCompleted: apple.isCompleted
        )
    }

    private func reminderFingerprint(title: String, isCompleted: Bool) -> String {
        stableHash("\(title)\u{0}\(isCompleted)")
    }

    private static func link(for record: ReminderSyncRecord) -> ReminderSyncLink {
        ReminderSyncLink(
            appleID: record.appleReminderID,
            skylightID: record.skylightItemID,
            lastAppleModifiedAt: record.lastAppleModifiedAt,
            lastSkylightModifiedAt: record.lastSkylightModifiedAt,
            baselineTitle: record.lastSyncedTitle,
            baselineCompleted: record.lastSyncedCompleted
        )
    }

    private func nonemptyTitle(_ value: String?) -> String {
        let title = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled" : title
    }

    private func mealSlotKey(
        noteID: String,
        meal: PlannedMeal,
        occurrences: inout [String: Int]
    ) -> String {
        let base = [meal.day.lowercased(), meal.category.lowercased()].joined(separator: "\u{0}")
        let occurrence = occurrences[base, default: 0]
        occurrences[base] = occurrence + 1
        return "\(noteID)::meal::\(stableHash("\(base)\u{0}\(occurrence)"))"
    }

    private func stableHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func checkpoint(_ state: SyncState, dryRun: Bool) async throws {
        guard !dryRun else { return }
        try await stateStore.saveSyncState(state)
    }

    private func upsertPhotoRecord(_ record: PhotoSyncRecord, in state: inout SyncState) {
        state.photos.removeAll { $0.id == record.id }
        state.photos.append(record)
    }

    private func recordManagedAlbum(
        mappingID: UUID,
        frameID: String,
        albumID: String,
        in state: inout SyncState
    ) {
        let record = PhotoAlbumRecord(mappingID: mappingID, frameID: frameID, albumID: albumID)
        state.photoAlbums.removeAll { $0.id == record.id }
        state.photoAlbums.append(record)
    }

    private func upsertReminderRecord(_ record: ReminderSyncRecord, in state: inout SyncState) {
        state.reminders.removeAll {
            $0.mappingID == record.mappingID &&
                ($0.appleReminderID == record.appleReminderID ||
                    $0.skylightItemID == record.skylightItemID)
        }
        state.reminders.append(record)
    }

    private func upsertNoteRecord(_ record: NoteSyncRecord, in state: inout SyncState) {
        state.notes.removeAll { $0.id == record.id }
        state.notes.append(record)
    }
}

private struct PhotoDestinationResolution: Sendable {
    let id: String?
    let needsCreation: Bool
}

private struct ReminderDestinationResolution: Sendable {
    let id: String?
    let needsCreation: Bool
}

private struct MealRemoteReference: Codable, Sendable {
    let mealID: String
    let instanceISO: String

    func encoded() throws -> String {
        try JSONEncoder().encode(self).base64EncodedString()
    }

    static func decode(_ value: String) throws -> MealRemoteReference {
        guard let data = Data(base64Encoded: value),
              let reference = try? JSONDecoder().decode(MealRemoteReference.self, from: data) else {
            throw SyncCoordinatorError.invalidMealReference(value)
        }
        return reference
    }
}

private extension Sequence where Element: Identifiable, Element.ID == String {
    var firstByID: [String: Element] {
        reduce(into: [:]) { result, element in
            if result[element.id] == nil {
                result[element.id] = element
            }
        }
    }
}
