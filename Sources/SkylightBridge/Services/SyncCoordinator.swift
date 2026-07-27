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
    var chores = SyncDomainSummary()
    var recipes = SyncDomainSummary()
    var meals = SyncDomainSummary()

    var totalPlanned: Int {
        photos.planned + reminders.planned + chores.planned + recipes.planned + meals.planned
    }

    var totalApplied: Int {
        photos.applied + reminders.applied + chores.applied + recipes.applied + meals.applied
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
    case missingChoreReminderSource
    case missingChoreList(String)

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
        case .missingChoreReminderSource:
            "Apple Reminders is not available for chore synchronization."
        case let .missingChoreList(title):
            "The Apple Reminders list ‘\(title)’ could not be resolved."
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
    func syncReminderList(withID listID: String) throws -> AppleReminderListSnapshot
    func syncUpdateReminderList(
        withID listID: String,
        title: String?,
        colorHex: String?
    ) throws -> AppleReminderListSnapshot
    func syncReminders(in listID: String) async throws -> [AppleReminderSnapshot]
    func syncCreateReminder(in listID: String, draft: AppleReminderDraft) async throws -> AppleReminderSnapshot
    func syncUpdateReminder(withID reminderID: String, patch: AppleReminderPatch) async throws -> AppleReminderSnapshot
    func syncRemoveReminder(withID reminderID: String) async throws
}

@MainActor
protocol ChoreReminderSource: Sendable {
    func syncReminderLists() throws -> [AppleReminderListSnapshot]
    func syncCreateReminderList(named title: String) throws -> AppleReminderListSnapshot
    func syncChoreReminders(in listID: String, memberKey: String) async throws -> [ChoreReminderSnapshot]
    func syncCreateChoreReminder(
        in listID: String,
        draft: ChoreReminderDraft,
        memberKey: String
    ) throws -> ChoreReminderSnapshot
    func syncUpdateChoreReminder(
        withID reminderID: String,
        patch: ChoreReminderPatch,
        memberKey: String
    ) throws -> ChoreReminderSnapshot
    func syncSetChoreReminderCompletion(
        withID reminderID: String,
        completed: Bool,
        dueDate: Date?,
        memberKey: String
    ) throws -> ChoreReminderSnapshot
    func syncMoveChoreReminder(
        withID reminderID: String,
        toListID listID: String,
        memberKey: String
    ) throws -> ChoreReminderSnapshot
    func syncRemoveChoreReminder(withID reminderID: String) throws
    func syncDeleteReminderListIfEmpty(withID listID: String) async throws -> Bool
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
    func listAlbumMessages(
        frameID: String,
        albumID: String,
        page: Int?
    ) async throws -> SkylightPhotoMessagesResponse
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
    func updateMessageCaption(
        frameID: String,
        messageID: String,
        caption: String
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
    func updateList(
        frameID: String,
        listID: String,
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

    func listCategories(
        frameID: String
    ) async throws -> [SkylightResource<SkylightCategoryAttributes>]
    func listAllChores(
        frameID: String
    ) async throws -> [SkylightResource<SkylightChoreAttributes>]
    func listChores(
        frameID: String,
        before: String?,
        after: String?,
        includeLate: Bool?,
        filter: String?
    ) async throws -> [SkylightResource<SkylightChoreAttributes>]
    func createChore(
        frameID: String,
        request: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes>
    func updateChore(
        frameID: String,
        choreID: String,
        request: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes>
    func deleteChore(frameID: String, choreID: String, applyToAll: Bool) async throws
    func setChoreCompletion(
        frameID: String,
        seriesID: String,
        request: SkylightChoreCompletionRequest
    ) async throws

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

// Existing test and preview APIs predate the optional chores domain. Empty
// read defaults preserve those conformances; writes fail loudly if a caller
// enables chores without implementing the concrete Skylight endpoints.
extension SkylightSyncAPI {
    func listCategories(
        frameID _: String
    ) async throws -> [SkylightResource<SkylightCategoryAttributes>] { [] }

    func listAllChores(
        frameID _: String
    ) async throws -> [SkylightResource<SkylightChoreAttributes>] { [] }

    func listChores(
        frameID _: String,
        before _: String?,
        after _: String?,
        includeLate _: Bool?,
        filter _: String?
    ) async throws -> [SkylightResource<SkylightChoreAttributes>] { [] }

    func createChore(
        frameID _: String,
        request _: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes> {
        throw SyncCoordinatorError.missingChoreReminderSource
    }

    func updateChore(
        frameID _: String,
        choreID _: String,
        request _: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes> {
        throw SyncCoordinatorError.missingChoreReminderSource
    }

    func deleteChore(frameID _: String, choreID _: String, applyToAll _: Bool) async throws {
        throw SyncCoordinatorError.missingChoreReminderSource
    }

    func setChoreCompletion(
        frameID _: String,
        seriesID _: String,
        request _: SkylightChoreCompletionRequest
    ) async throws {
        throw SyncCoordinatorError.missingChoreReminderSource
    }
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
    func syncReminderList(withID listID: String) throws -> AppleReminderListSnapshot {
        try reminderList(withID: listID)
    }

    func syncUpdateReminderList(
        withID listID: String,
        title: String?,
        colorHex: String?
    ) throws -> AppleReminderListSnapshot {
        try updateReminderList(withID: listID, title: title, colorHex: colorHex)
    }

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

extension AppleRemindersStore: ChoreReminderSource {
    func syncReminderLists() throws -> [AppleReminderListSnapshot] { try lists() }

    func syncCreateReminderList(named title: String) throws -> AppleReminderListSnapshot {
        try createList(named: title)
    }

    func syncChoreReminders(
        in listID: String,
        memberKey: String
    ) async throws -> [ChoreReminderSnapshot] {
        try await choreReminders(in: listID, memberKey: memberKey)
    }

    func syncCreateChoreReminder(
        in listID: String,
        draft: ChoreReminderDraft,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try createChoreReminder(in: listID, draft: draft, memberKey: memberKey)
    }

    func syncUpdateChoreReminder(
        withID reminderID: String,
        patch: ChoreReminderPatch,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try updateChoreReminder(withID: reminderID, patch: patch, memberKey: memberKey)
    }

    func syncSetChoreReminderCompletion(
        withID reminderID: String,
        completed: Bool,
        dueDate: Date?,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try setChoreReminderCompletion(
            withID: reminderID,
            completed: completed,
            dueDate: dueDate,
            memberKey: memberKey
        )
    }

    func syncMoveChoreReminder(
        withID reminderID: String,
        toListID listID: String,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try moveChoreReminder(withID: reminderID, toListID: listID, memberKey: memberKey)
    }

    func syncRemoveChoreReminder(withID reminderID: String) throws {
        try removeReminder(withID: reminderID)
    }

    func syncDeleteReminderListIfEmpty(withID listID: String) async throws -> Bool {
        try await deleteListIfEmpty(withID: listID)
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
    private let choreReminderSource: (any ChoreReminderSource)?
    private let notesSource: any NotesSyncSource
    private let imageConverter: any SyncImageConverting
    private let api: any SkylightSyncAPI
    private let stateStore: any SyncStatePersisting
    private let mealDateResolver: any MealDateResolving
    private let recipeClassifier: (any RecipeClassifying)?
    private let now: @Sendable () -> Date

    init(
        photoSource: any PhotoSyncSource,
        reminderSource: any ReminderSyncSource,
        choreReminderSource: (any ChoreReminderSource)? = nil,
        notesSource: any NotesSyncSource,
        imageConverter: any SyncImageConverting,
        api: any SkylightSyncAPI,
        stateStore: any SyncStatePersisting,
        mealDateResolver: any MealDateResolving = DefaultMealDateResolver(),
        recipeClassifier: (any RecipeClassifying)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.photoSource = photoSource
        self.reminderSource = reminderSource
        self.choreReminderSource = choreReminderSource ?? reminderSource as? any ChoreReminderSource
        self.notesSource = notesSource
        self.imageConverter = imageConverter
        self.api = api
        self.stateStore = stateStore
        self.mealDateResolver = mealDateResolver
        self.recipeClassifier = recipeClassifier
        self.now = now
    }

    @MainActor
    static func live(
        apiClient: SkylightAPIClient,
        stateStore: SyncStateStore = SyncStateStore()
    ) -> SyncCoordinator {
        let remindersStore = AppleRemindersStore()
        return SyncCoordinator(
            photoSource: ApplePhotoLibrary(),
            reminderSource: remindersStore,
            choreReminderSource: remindersStore,
            notesSource: AppleNotesStore(),
            imageConverter: ImageConversionService(),
            api: apiClient,
            stateStore: stateStore,
            recipeClassifier: RecipeIntelligence()
        )
    }

    func sync(configuration: AppConfiguration) async throws -> SyncRunSummary {
        var summary = SyncRunSummary(dryRun: configuration.dryRun)
       guard configuration.hasEnabledSync else {
           return summary
       }

        albumMessageCache.removeAll()

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
        summary.chores = try await syncChores(
            mappings: configuration.choreMappings.filter {
                $0.isEnabled && ($0.frameID.isEmpty || $0.frameID == frameID)
            },
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
        let listRecordCount = state.reminderLists.count
        state.reminderLists.removeAll {
            $0.mappingID == mappingID && $0.frameID == frameID
        }
        if state.reminderLists.count != listRecordCount {
            try await stateStore.saveSyncState(state)
        }
        return affected
    }

    /// Forgets a chore mapping's identity links and optionally removes the
    /// linked series from one side. The Reminders lists themselves are kept.
    /// Tears down a chore mapping: removes the chore items from the side(s) the
    /// mode does not preserve, forgets their sync records, and deletes the
    /// auto-created Apple chore lists once they are empty. Deletions are
    /// best-effort so one failure cannot strand the rest of the cleanup.
    func teardownChoreMapping(
        mappingID: UUID,
        frameID: String,
        mode: ChoreTeardownMode,
        appleListIDs: [String]
    ) async throws -> ChoreTeardownResult {
        var state = try await stateStore.loadSyncState()
        let records = state.chores
            .filter { $0.mappingID == mappingID && $0.frameID == frameID }
            .sorted { $0.appleReminderID < $1.appleReminderID }
        var result = ChoreTeardownResult()
        for record in records {
            if mode.removesSkylight {
                try? await api.deleteChore(
                    frameID: frameID,
                    choreID: record.skylightSeriesID,
                    applyToAll: record.lastSyncedRecurrence != nil
                )
                result.skylightItemsRemoved += 1
            }
            if mode.removesAppleReminders {
                try? await choreReminderSource?.syncRemoveChoreReminder(
                    withID: record.appleReminderID
                )
                result.appleItemsRemoved += 1
            }
            state.chores.removeAll { $0.id == record.id }
            try await stateStore.saveSyncState(state)
        }
        // The auto-created lists only make sense to remove when the Apple side
        // is being cleared; otherwise deleting them would take the preserved
        // reminders with them. deleteListIfEmpty guards against removing a list
        // the user has since put their own reminders into.
        if mode.removesAppleReminders, let source = choreReminderSource {
            for listID in appleListIDs where !listID.trimmed.isEmpty {
                if (try? await source.syncDeleteReminderListIfEmpty(withID: listID)) == true {
                    result.listsRemoved += 1
                }
            }
        }
        return result
    }

    func purgeChoreMapping(
        mappingID: UUID,
        frameID: String,
        side: ReminderMappingCleanupSide = .none
    ) async throws -> Int {
        var state = try await stateStore.loadSyncState()
        let records = state.chores
            .filter { $0.mappingID == mappingID && $0.frameID == frameID }
            .sorted { $0.appleReminderID < $1.appleReminderID }
        var affected = 0
        for record in records {
            switch side {
            case .skylight:
                try? await api.deleteChore(
                    frameID: frameID,
                    choreID: record.skylightSeriesID,
                    applyToAll: record.lastSyncedRecurrence != nil
                )
                affected += 1
            case .appleReminders:
                try? await choreReminderSource?.syncRemoveChoreReminder(
                    withID: record.appleReminderID
                )
                affected += 1
            case .none:
                break
            }
            state.chores.removeAll { $0.id == record.id }
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
                let caption = normalizedPhotoCaption(mapping.selectedPhotoNames[asset.id])
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
                    let needsCaptionUpdate = caption.map { $0 != existing.lastSyncedCaption } ?? false
                    summary.planned += (needsAdd ? 1 : 0)
                        + (oldAlbumIDs.isEmpty ? 0 : 1)
                        + (needsCaptionUpdate ? 1 : 0)
                    guard !dryRun, needsAdd || !oldAlbumIDs.isEmpty || needsCaptionUpdate else {
                        continue
                    }
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
                   if needsCaptionUpdate, let caption {
                       let dedupCaption = PhotoDeduplication.caption(
                           withUserCaption: caption,
                           renderedHash: existing.renderedHash
                       )
                       _ = try await api.updateMessageCaption(
                           frameID: frameID,
                           messageID: existing.skylightMessageID,
                           caption: dedupCaption ?? caption
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
                        lastSyncedAt: now(),
                        lastSyncedCaption: caption ?? existing.lastSyncedCaption
                    ), in: &state)
                    try await checkpoint(state, dryRun: dryRun)
                    continue
                }

               summary.planned += 1
               if !dryRun {
                    let dedupCaption = PhotoDeduplication.caption(
                        withUserCaption: caption,
                        renderedHash: converted.sha256
                    )
                    if let duplicateMessageID = try await findDuplicatePhoto(
                        renderedHash: converted.sha256,
                        frameID: frameID,
                        albumID: destinationID
                    ) {
                        try await api.addMessages(
                            frameID: frameID,
                            albumIDs: [destinationID],
                            messageIDs: [duplicateMessageID]
                        )
                        if let dedupCaption, dedupCaption != caption {
                            _ = try await api.updateMessageCaption(
                                frameID: frameID,
                                messageID: duplicateMessageID,
                                caption: dedupCaption
                            )
                        }
                        upsertPhotoRecord(
                            PhotoSyncRecord(
                                mappingID: mapping.id,
                                frameID: frameID,
                                destinationAlbumID: destinationID,
                                appleAssetID: asset.id,
                                renderedHash: converted.sha256,
                                skylightMessageID: duplicateMessageID,
                                skylightAlbumIDs: [destinationID],
                                lastSyncedAt: now(),
                                lastSyncedCaption: caption
                            ),
                            in: &state
                        )
                        try await checkpoint(state, dryRun: dryRun)
                        summary.applied += 1
                        continue
                    }
                    let newMessageID = try await uploadPhoto(
                        converted,
                        frameID: frameID,
                        destinationAlbumID: destinationID,
                        caption: dedupCaption
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
                            lastSyncedAt: now(),
                            lastSyncedCaption: caption
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

    private func normalizedPhotoCaption(_ value: String?) -> String? {
        let caption = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return caption.isEmpty ? nil : caption
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

    private var albumMessageCache: [String: [SkylightResource<SkylightPhotoMessageAttributes>]] = [:]

    private func findDuplicatePhoto(
        renderedHash: String,
        frameID: String,
        albumID: String
    ) async throws -> String? {
        let cacheKey = "\(frameID):\(albumID)"
        if let cached = albumMessageCache[cacheKey] {
            return PhotoDeduplication.findDuplicate(
                renderedHash: renderedHash,
                in: cached
            )
        }
        var allMessages: [SkylightResource<SkylightPhotoMessageAttributes>] = []
        var page: Int? = nil
        repeat {
            let response = try await api.listAlbumMessages(
                frameID: frameID,
                albumID: albumID,
                page: page
            )
            allMessages.append(contentsOf: response.data)
            page = response.meta?.nextPageToken.flatMap(Int.init)
        } while page != nil
        albumMessageCache[cacheKey] = allMessages
        return PhotoDeduplication.findDuplicate(
            renderedHash: renderedHash,
            in: allMessages
        )
    }

    private func uploadPhoto(
        _ image: AppleConvertedImage,
        frameID: String,
        destinationAlbumID: String,
        caption: String?
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
            caption: caption
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
            let appleList = try await reminderSource.syncReminderList(withID: mapping.sourceListID)
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
            if let destinationID = destination.id,
               let attributes = destination.attributes {
                let listSummary = try await syncReminderListMetadata(
                    mapping: mapping,
                    frameID: frameID,
                    appleList: appleList,
                    skylightListID: destinationID,
                    skylightAttributes: attributes,
                    dryRun: dryRun,
                    state: &state
                )
                summary.planned += listSummary.planned
                summary.applied += listSummary.applied
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
                let secondaryPairs = ReminderSyncPlanner.titleOnlyAdoptionPairs(
                    apple: appleSnapshots,
                    skylight: remoteSnapshots,
                    primaryPairs: pairs
                )
                for pair in secondaryPairs {
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
                if !secondaryPairs.isEmpty {
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
            guard let configured = lists.first(where: { $0.id == configuredID }) else {
                throw SyncCoordinatorError.invalidReminderDestination(mapping.id)
            }
            return ReminderDestinationResolution(
                id: configuredID,
                attributes: configured.attributes,
                needsCreation: false
            )
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
            return ReminderDestinationResolution(
                id: existing.id,
                attributes: existing.attributes,
                needsCreation: false
            )
        }
        guard !dryRun else {
            return ReminderDestinationResolution(id: nil, attributes: nil, needsCreation: true)
        }
        let created = try await api.createList(
            frameID: frameID,
            request: SkylightListRequest(label: title, kind: mapping.destinationKind)
        )
        return ReminderDestinationResolution(
            id: created.id,
            attributes: created.attributes,
            needsCreation: true
        )
    }

    private func syncReminderListMetadata(
        mapping: ReminderListMapping,
        frameID: String,
        appleList: AppleReminderListSnapshot,
        skylightListID: String,
        skylightAttributes: SkylightListAttributes,
        dryRun: Bool,
        state: inout SyncState
    ) async throws -> SyncDomainSummary {
        var summary = SyncDomainSummary()
        let appleTitle = appleList.title.trimmed
        let skylightTitle = (skylightAttributes.label ?? "").trimmed
        let appleColor = ReminderListColor.normalizedHex(appleList.colorHex)
        let skylightColor = ReminderListColor.normalizedHex(skylightAttributes.color)
        guard !appleTitle.isEmpty, !skylightTitle.isEmpty else { return summary }

        guard let existing = state.reminderLists.first(where: {
            $0.mappingID == mapping.id &&
                $0.frameID == frameID &&
                $0.appleListID == appleList.id &&
                $0.skylightListID == skylightListID
        }) else {
            guard !dryRun else { return summary }
            upsertReminderListRecord(ReminderListSyncRecord(
                mappingID: mapping.id,
                frameID: frameID,
                appleListID: appleList.id,
                skylightListID: skylightListID,
                lastSyncedAppleTitle: appleTitle,
                lastSyncedSkylightTitle: skylightTitle,
                lastSyncedAppleColor: appleColor,
                lastSyncedSkylightColor: skylightColor
            ), in: &state)
            try await checkpoint(state, dryRun: false)
            return summary
        }

        let titleAction = ReminderListMetadataPlanner.plan(
            appleTitle: appleTitle,
            skylightTitle: skylightTitle,
            link: ReminderListMetadataLink(
                baselineAppleTitle: existing.lastSyncedAppleTitle,
                baselineSkylightTitle: existing.lastSyncedSkylightTitle
            ),
            direction: mapping.direction,
            conflictPolicy: mapping.conflictPolicy
        )
        let colorMetadataIsInitialized = existing.lastSyncedAppleColor != nil
            || existing.lastSyncedSkylightColor != nil
        let colorAction = colorMetadataIsInitialized
            ? ReminderListColorMetadataPlanner.plan(
                appleColor: appleColor,
                skylightColor: skylightColor,
                link: ReminderListColorMetadataLink(
                    baselineAppleColor: ReminderListColor.normalizedHex(existing.lastSyncedAppleColor),
                    baselineSkylightColor: ReminderListColor.normalizedHex(existing.lastSyncedSkylightColor)
                ),
                direction: mapping.direction,
                conflictPolicy: mapping.conflictPolicy
            )
            : nil
        guard titleAction != nil || colorAction != nil else {
            guard !dryRun else { return summary }
            upsertReminderListRecord(ReminderListSyncRecord(
                mappingID: mapping.id,
                frameID: frameID,
                appleListID: appleList.id,
                skylightListID: skylightListID,
                lastSyncedAppleTitle: appleTitle,
                lastSyncedSkylightTitle: skylightTitle,
                lastSyncedAppleColor: appleColor,
                lastSyncedSkylightColor: skylightColor
            ), in: &state)
            try await checkpoint(state, dryRun: false)
            return summary
        }

        let remoteTitle = titleForRemoteUpdate(titleAction)
        let remoteColor = colorForRemoteUpdate(colorAction)
        let updatedAppleTitle = titleForAppleUpdate(titleAction)
        let updatedAppleColor = colorForAppleUpdate(colorAction)
        summary.planned = (remoteTitle != nil || remoteColor != nil ? 1 : 0)
            + (updatedAppleTitle != nil || updatedAppleColor != nil ? 1 : 0)
        guard !dryRun else { return summary }

        var syncedTitles = (apple: appleTitle, skylight: skylightTitle)
        var syncedColors = (apple: appleColor, skylight: skylightColor)
        if remoteTitle != nil || remoteColor != nil {
            let updated = try await api.updateList(
                frameID: frameID,
                listID: skylightListID,
                request: SkylightListRequest(
                    label: remoteTitle,
                    color: remoteColor,
                    kind: skylightAttributes.kind,
                    hideOnDevice: skylightAttributes.hideOnDevice
                )
            )
            syncedTitles.skylight = (updated.attributes.label ?? remoteTitle ?? skylightTitle).trimmed
            syncedColors.skylight = ReminderListColor.normalizedHex(updated.attributes.color)
                ?? remoteColor
                ?? skylightColor
        }
        if updatedAppleTitle != nil || updatedAppleColor != nil {
            let updated = try await reminderSource.syncUpdateReminderList(
                withID: appleList.id,
                title: updatedAppleTitle,
                colorHex: updatedAppleColor
            )
            syncedTitles.apple = updated.title.trimmed
            syncedColors.apple = ReminderListColor.normalizedHex(updated.colorHex)
                ?? updatedAppleColor
                ?? appleColor
        }

        upsertReminderListRecord(ReminderListSyncRecord(
            mappingID: mapping.id,
            frameID: frameID,
            appleListID: appleList.id,
            skylightListID: skylightListID,
            lastSyncedAppleTitle: syncedTitles.apple,
            lastSyncedSkylightTitle: syncedTitles.skylight,
            lastSyncedAppleColor: syncedColors.apple,
            lastSyncedSkylightColor: syncedColors.skylight
        ), in: &state)
        try await checkpoint(state, dryRun: false)
        summary.applied = summary.planned
        return summary
    }

    private func titleForRemoteUpdate(
        _ action: ReminderListMetadataAction?
    ) -> String? {
        guard case let .updateRemote(title)? = action else { return nil }
        return title
    }

    private func titleForAppleUpdate(
        _ action: ReminderListMetadataAction?
    ) -> String? {
        guard case let .updateApple(title)? = action else { return nil }
        return title
    }

    private func colorForRemoteUpdate(
        _ action: ReminderListColorMetadataAction?
    ) -> String? {
        guard case let .updateRemote(color)? = action else { return nil }
        return color
    }

    private func colorForAppleUpdate(
        _ action: ReminderListColorMetadataAction?
    ) -> String? {
        guard case let .updateApple(color)? = action else { return nil }
        return color
    }

    private func syncChores(
        mappings: [ChoreMapping],
        frameID: String,
        dryRun: Bool,
        state: inout SyncState
    ) async throws -> SyncDomainSummary {
        guard !mappings.isEmpty else { return SyncDomainSummary() }
        guard let choreReminderSource else {
            throw SyncCoordinatorError.missingChoreReminderSource
        }
        var summary = SyncDomainSummary()
        let todayDate = Calendar.current.startOfDay(for: now())
        let today = Self.isoDay(todayDate)
        let yesterday = Self.isoDay(Calendar.current.date(byAdding: .day, value: -1, to: todayDate)!)
        let tomorrow = Self.isoDay(Calendar.current.date(byAdding: .day, value: 1, to: todayDate)!)

        for mapping in mappings {
            let enabledLinks = mapping.memberLinks.filter(\.isEnabled)
            let enabledKeys = Set(enabledLinks.map(\.memberKey))
            state.chores.removeAll {
                $0.mappingID == mapping.id && $0.frameID == frameID && !enabledKeys.contains($0.memberKey)
            }
            guard !enabledLinks.isEmpty else { continue }

            var listIDByMember: [String: String] = [:]
            var appleSnapshots: [ChoreReminderSnapshot] = []
            var availableLists = try await choreReminderSource.syncReminderLists()
                .filter(\.allowsContentModifications)
            for link in enabledLinks {
                let configuredID = link.appleListID?.trimmed ?? ""
                let resolvedByID = configuredID.isEmpty
                    ? nil
                    : availableLists.first(where: { $0.id == configuredID })
                let resolved = resolvedByID ?? availableLists.first(where: {
                        $0.title.localizedCaseInsensitiveCompare(link.appleListTitle) == .orderedSame
                    })
                if let resolved {
                    listIDByMember[link.memberKey] = resolved.id
                    appleSnapshots += try await choreReminderSource.syncChoreReminders(
                        in: resolved.id,
                        memberKey: link.memberKey
                    )
                } else {
                    summary.planned += 1
                    guard !dryRun else { continue }
                    let created = try await choreReminderSource.syncCreateReminderList(
                        named: link.appleListTitle
                    )
                    availableLists.append(created)
                    listIDByMember[link.memberKey] = created.id
                    summary.applied += 1
                }
            }

            let allResources = try await api.listAllChores(frameID: frameID)
            let todayResources = try await api.listChores(
                frameID: frameID,
                before: tomorrow,
                after: yesterday,
                includeLate: true,
                filter: nil
            )
            let todayByID = todayResources.reduce(into: [String: SkylightResource<SkylightChoreAttributes>]()) {
                let seriesID = Self.choreSeriesID($1)
                if $0[seriesID] == nil || $1.attributes.start == today {
                    $0[seriesID] = $1
                }
            }
            let records = state.chores.filter { $0.mappingID == mapping.id && $0.frameID == frameID }
            let syncTime = now()
            let remoteSnapshots = allResources.compactMap { resource -> SkylightChoreSnapshot? in
                let memberKey = Self.choreMemberKey(resource, links: enabledLinks)
                guard enabledKeys.contains(memberKey) else { return nil }
                let recurrence = Self.choreRecurrence(resource.attributes.recurrenceSet)
                let seriesID = Self.choreSeriesID(resource)
                let todayResource = todayByID[seriesID]
                let status = todayResource?.attributes.status ?? resource.attributes.status
                let fingerprint = Self.choreFingerprint(
                    resource: resource,
                    memberKey: memberKey,
                    todayStatus: status
                )
                let record = records.first { $0.skylightSeriesID == seriesID }
                let modifiedAt = record?.contentFingerprint == fingerprint
                    ? record!.lastSkylightModifiedAt
                    : syncTime
                return SkylightChoreSnapshot(
                    id: seriesID,
                    title: resource.attributes.summary ?? "Untitled Chore",
                    notes: resource.attributes.description,
                    memberKey: memberKey,
                    recurrenceRaw: resource.attributes.recurrenceSet ?? [],
                    recurrence: recurrence.rule,
                    recurrenceUnsupported: recurrence.unsupported,
                    todayStatus: status,
                    startDate: Self.parseChoreDueDate(
                        day: resource.attributes.start,
                        time: resource.attributes.startTime,
                        recurrence: recurrence.rule
                    ),
                    modifiedAt: modifiedAt
                )
            }

            // EventKit may represent the next occurrence of a completed
            // repeating reminder with a new calendar item identifier. Rebind
            // that occurrence by the mapping's stable title/member identity
            // before the planner interprets the old identifier as a deletion.
            var activeRecords = records
            let liveAppleIDs = Set(appleSnapshots.map(\.id))
            var claimedAppleIDs = Set(activeRecords.compactMap {
                liveAppleIDs.contains($0.appleReminderID) ? $0.appleReminderID : nil
            })
            var reboundCount = 0
            for index in activeRecords.indices
            where !liveAppleIDs.contains(activeRecords[index].appleReminderID) {
                let record = activeRecords[index]
                let candidates = appleSnapshots.filter {
                    !claimedAppleIDs.contains($0.id) &&
                        $0.memberKey == record.memberKey &&
                        $0.title.trimmed.localizedCaseInsensitiveCompare(
                            record.lastSyncedTitle?.trimmed ?? ""
                        ) == .orderedSame
                }
                guard candidates.count == 1, let replacement = candidates.first else { continue }
                activeRecords[index].appleReminderID = replacement.id
                activeRecords[index].lastAppleModifiedAt = replacement.modifiedAt
                claimedAppleIDs.insert(replacement.id)
                Self.upsertChoreRecord(activeRecords[index], state: &state)
                reboundCount += 1
            }
            // When a recurring reminder was completed (either by the user or
            // by a prior sync propagating a Skylight completion), EventKit
            // generates a new uncompleted occurrence with a fresh identifier.
            // The old completed reminder is still returned by fetchReminders,
            // so the ID-based rebind above does not fire. Without this second
            // pass the link stays on the stale completed reminder, the new
            // occurrence is unlinked, and each complete→reopen cycle accumulates
            // a duplicate Apple Reminder. Rebind the link to the new occurrence
            // and drop the stale completed reminder from the snapshot set so
            // the planner never sees it as an independent item.
            var staleCompletedIDs: Set<String> = []
            for index in activeRecords.indices {
                let record = activeRecords[index]
                guard liveAppleIDs.contains(record.appleReminderID),
                      let linked = appleSnapshots.first(where: { $0.id == record.appleReminderID }),
                      linked.isCompleted,
                      linked.recurrence != nil else { continue }
                let candidates = appleSnapshots.filter {
                    !claimedAppleIDs.contains($0.id) &&
                        !$0.isCompleted &&
                        $0.recurrence != nil &&
                        $0.memberKey == record.memberKey &&
                        $0.title.trimmed.localizedCaseInsensitiveCompare(
                            record.lastSyncedTitle?.trimmed ?? linked.title.trimmed
                        ) == .orderedSame
                }
                guard let replacement = candidates.sorted(by: Self.preferredChoreOccurrence).first else {
                    continue
                }
                let duplicateIDs = Set(candidates.lazy.map(\.id).filter { $0 != replacement.id })
                staleCompletedIDs.insert(record.appleReminderID)
                activeRecords[index].appleReminderID = replacement.id
                activeRecords[index].lastAppleModifiedAt = replacement.modifiedAt
                claimedAppleIDs.insert(replacement.id)
                Self.upsertChoreRecord(activeRecords[index], state: &state)
                reboundCount += 1
                summary.planned += duplicateIDs.count
                if !dryRun {
                    for duplicateID in duplicateIDs.sorted() {
                        try await choreReminderSource.syncRemoveChoreReminder(withID: duplicateID)
                        summary.applied += 1
                    }
                }
                appleSnapshots.removeAll { duplicateIDs.contains($0.id) }
            }
            if !staleCompletedIDs.isEmpty {
                appleSnapshots.removeAll { staleCompletedIDs.contains($0.id) }
            }
            let adoptionPairs = ChoreSyncPlanner.adoptionPairs(
                apple: appleSnapshots,
                skylight: remoteSnapshots,
                links: activeRecords.map(Self.choreLink)
            )
            let appleForAdoption = Dictionary(uniqueKeysWithValues: appleSnapshots.map { ($0.id, $0) })
            let remoteForAdoption = Dictionary(uniqueKeysWithValues: remoteSnapshots.map { ($0.id, $0) })
            for pair in adoptionPairs {
                guard let apple = appleForAdoption[pair.appleID],
                      let remote = remoteForAdoption[pair.skylightID] else { continue }
                let adopted = Self.choreRecord(
                    mappingID: mapping.id,
                    frameID: frameID,
                    apple: apple,
                    remote: remote,
                    today: today
                )
                Self.upsertChoreRecord(adopted, state: &state)
                activeRecords.removeAll {
                    $0.appleReminderID == pair.appleID || $0.skylightSeriesID == pair.skylightID
                }
                activeRecords.append(adopted)
            }
            if !adoptionPairs.isEmpty || reboundCount > 0 {
                try await checkpoint(state, dryRun: dryRun)
            }

            // Chore Chart represents a shared household schedule. Unlike a
            // general Reminders list mapping, it always mirrors changes in
            // both directions, including configurations saved by older builds.
            let actions = ChoreSyncPlanner.plan(
                apple: appleSnapshots,
                skylight: remoteSnapshots,
                links: activeRecords.map(Self.choreLink),
                direction: .twoWay,
                conflictPolicy: mapping.conflictPolicy,
                today: today,
                todayDate: todayDate
            )

            // When both sides independently reached the same occurrence state,
            // there is no completion action to execute. Advance the persisted
            // baseline anyway so the next sync can distinguish a later reopen
            // from the already-reconciled occurrence.
            for record in activeRecords {
                guard let apple = appleForAdoption[record.appleReminderID],
                      let remote = remoteForAdoption[record.skylightSeriesID] else { continue }
                let remoteCompleted = remote.todayStatus == .complete || remote.todayStatus == .skipped
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: todayDate)
                    ?? .distantFuture
                let appleRolledForward = if let baseline = record.baselineDueDate,
                                             let due = apple.dueDate {
                    due > baseline && baseline < tomorrow
                } else {
                    false
                }
                let appleCompleted = apple.isCompleted || appleRolledForward
                guard appleCompleted == remoteCompleted,
                      let index = state.chores.firstIndex(where: { $0.id == record.id }) else { continue }
                state.chores[index].baselineCompletedInstanceDate = remoteCompleted ? today : nil
                state.chores[index].baselineDueDate = apple.dueDate
                state.chores[index].lastAppleModifiedAt = apple.modifiedAt
                state.chores[index].lastSkylightModifiedAt = remote.modifiedAt
                state.chores[index].contentFingerprint = Self.choreFingerprint(snapshot: remote)
            }
            summary.planned += actions.count
            guard !dryRun else { continue }

            let appleByID = Dictionary(uniqueKeysWithValues: appleSnapshots.map { ($0.id, $0) })
            let remoteByID = Dictionary(uniqueKeysWithValues: remoteSnapshots.map { ($0.id, $0) })

            for action in actions {
                switch action {
                case let .createRemote(appleID):
                    guard let apple = appleByID[appleID] else { continue }
                    let created = try await api.createChore(
                        frameID: frameID,
                        request: Self.choreRequest(apple: apple, today: today)
                    )
                    let remote = Self.remoteSnapshot(
                        created,
                        memberKey: apple.memberKey,
                        status: apple.isCompleted ? .complete : .pending,
                        modifiedAt: now()
                    )
                    Self.upsertChoreRecord(Self.choreRecord(
                        mappingID: mapping.id,
                        frameID: frameID,
                        apple: apple,
                        remote: remote,
                        today: today
                    ), state: &state)

                case let .createApple(seriesID):
                    guard let remote = remoteByID[seriesID],
                          let listID = listIDByMember[remote.memberKey] else { continue }
                    let apple = try await choreReminderSource.syncCreateChoreReminder(
                        in: listID,
                        draft: ChoreReminderDraft(
                            title: remote.title,
                            notes: remote.notes,
                            dueDate: remote.startDate ?? todayDate,
                            recurrence: remote.recurrence
                        ),
                        memberKey: remote.memberKey
                    )
                    Self.upsertChoreRecord(Self.choreRecord(
                        mappingID: mapping.id,
                        frameID: frameID,
                        apple: apple,
                        remote: remote,
                        today: today
                    ), state: &state)

                case let .updateRemote(appleID, seriesID):
                    guard let apple = appleByID[appleID], let remote = remoteByID[seriesID] else { continue }
                    _ = try await api.updateChore(
                        frameID: frameID,
                        choreID: seriesID,
                        request: Self.choreRequest(
                            apple: apple,
                            today: today,
                            preserveRecurrence: apple.recurrenceUnsupported ||
                                (state.chores.first {
                                    $0.mappingID == mapping.id && $0.skylightSeriesID == seriesID
                                }?.recurrenceDegraded == true)
                        )
                    )
                    let updatedRemote = SkylightChoreSnapshot(
                        id: remote.id,
                        title: apple.title,
                        notes: apple.notes,
                        memberKey: apple.memberKey,
                        recurrenceRaw: apple.recurrence.map { [RecurrenceRuleConverter.format($0)] }
                            ?? remote.recurrenceRaw,
                        recurrence: apple.recurrence ?? remote.recurrence,
                        recurrenceUnsupported: apple.recurrenceUnsupported,
                        todayStatus: remote.todayStatus,
                        startDate: apple.dueDate,
                        modifiedAt: now()
                    )
                    Self.upsertChoreRecord(Self.choreRecord(
                        mappingID: mapping.id, frameID: frameID,
                        apple: apple, remote: updatedRemote, today: today
                    ), state: &state)

                case let .updateApple(appleID, seriesID):
                    guard var apple = appleByID[appleID], let remote = remoteByID[seriesID] else { continue }
                    if apple.memberKey != remote.memberKey,
                       let listID = listIDByMember[remote.memberKey] {
                        apple = try await choreReminderSource.syncMoveChoreReminder(
                            withID: appleID, toListID: listID, memberKey: remote.memberKey
                        )
                    }
                    apple = try await choreReminderSource.syncUpdateChoreReminder(
                        withID: appleID,
                        patch: ChoreReminderPatch(
                            title: remote.title,
                            notes: remote.notes,
                            dueDate: remote.startDate ?? apple.dueDate,
                            recurrence: remote.recurrence,
                            replaceRecurrence: !remote.recurrenceUnsupported
                        ),
                        memberKey: remote.memberKey
                    )
                    Self.upsertChoreRecord(Self.choreRecord(
                        mappingID: mapping.id, frameID: frameID,
                        apple: apple, remote: remote, today: today
                    ), state: &state)

                case let .completeRemote(seriesID, status):
                    // Skylight ties `instance_date`/`instance_time` to a specific
                    // occurrence of a recurring chore and rejects them (HTTP 422)
                    // for one-off chores, where the completion applies to the
                    // whole chore. Only send them when the chore is recurring.
                    let remoteIsRecurring = !(remoteByID[seriesID]?.recurrenceRaw.isEmpty ?? true)
                    try await api.setChoreCompletion(
                        frameID: frameID,
                        seriesID: seriesID,
                        request: SkylightChoreCompletionRequest(
                            status: status,
                            instanceDate: remoteIsRecurring ? today : nil,
                            instanceTime: remoteIsRecurring
                                ? (remoteByID[seriesID]?.startDate.map(Self.choreTime) ?? "06:00")
                                : nil
                        )
                    )
                    if let index = state.chores.firstIndex(where: {
                        $0.mappingID == mapping.id && $0.skylightSeriesID == seriesID
                    }) {
                        state.chores[index].baselineCompletedInstanceDate = status == .pending ? nil : today
                        state.chores[index].lastSkylightModifiedAt = now()
                        if let apple = appleByID[state.chores[index].appleReminderID] {
                            state.chores[index].baselineDueDate = apple.dueDate
                            state.chores[index].lastAppleModifiedAt = apple.modifiedAt
                        }
                        if let remote = remoteByID[seriesID] {
                            state.chores[index].contentFingerprint = Self.choreFingerprint(
                                snapshot: remote,
                                todayStatus: status
                            )
                        }
                    }

                case let .completeApple(appleID, completed):
                    guard let remoteRecord = state.chores.first(where: {
                        $0.mappingID == mapping.id && $0.appleReminderID == appleID
                    }) else { continue }
                    let apple = try await choreReminderSource.syncSetChoreReminderCompletion(
                        withID: appleID,
                        completed: completed,
                        dueDate: completed ? nil : todayDate,
                        memberKey: remoteRecord.memberKey
                    )
                    if let index = state.chores.firstIndex(where: { $0.id == remoteRecord.id }) {
                        state.chores[index].baselineCompletedInstanceDate = completed ? today : nil
                        state.chores[index].baselineDueDate = apple.dueDate
                        state.chores[index].lastAppleModifiedAt = apple.modifiedAt
                        if let remote = remoteByID[remoteRecord.skylightSeriesID] {
                            state.chores[index].lastSkylightModifiedAt = remote.modifiedAt
                            state.chores[index].contentFingerprint = Self.choreFingerprint(
                                snapshot: remote
                            )
                        }
                    }

                case let .deleteRemote(seriesID):
                    // `apply_to=all` clears an entire recurring series but is
                    // rejected (HTTP 400) for one-off chores, so scope it to the
                    // chore's recurrence.
                    let remoteIsRecurring = !(remoteByID[seriesID]?.recurrenceRaw.isEmpty ?? true)
                    try await api.deleteChore(
                        frameID: frameID,
                        choreID: seriesID,
                        applyToAll: remoteIsRecurring
                    )
                    state.chores.removeAll {
                        $0.mappingID == mapping.id && $0.skylightSeriesID == seriesID
                    }

                case let .deleteApple(appleID):
                    try await choreReminderSource.syncRemoveChoreReminder(withID: appleID)
                    state.chores.removeAll {
                        $0.mappingID == mapping.id && $0.appleReminderID == appleID
                    }
                }
                summary.applied += 1
                try await checkpoint(state, dryRun: dryRun)
            }
        }
        return summary
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
        let categoryContext = try await resolveRecipeCategoryContext(
            selection: selection,
            frameID: frameID,
            needed: !noteSummaries.isEmpty
        )
        var summary = SyncDomainSummary()

        // One-time cache repair: pushes made while the classifier was
        // unavailable used to cache the fallback (first) category as if the
        // model had chosen it, which blocked the classification retrofit
        // forever. Clear those entries once so the retrofit can reclassify;
        // classifyRecipePush no longer caches fallback assignments.
        if categoryContext.isAutomatic,
           let fallbackID = categoryContext.fallbackCategoryID,
           !state.recipeFallbackCacheClearedFrameIDs.contains(frameID) {
            for index in state.notes.indices
            where state.notes[index].kind == .recipes
                && state.notes[index].frameID == frameID
                && state.notes[index].autoCategoryID == fallbackID {
                state.notes[index].autoCategoryID = nil
            }
            state.recipeFallbackCacheClearedFrameIDs.insert(frameID)
            try await checkpoint(state, dryRun: dryRun)
        }

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
                categoryContext: categoryContext,
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
            categoryContext: categoryContext,
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
            let classification = await classifyRecipePush(
                draft: parsed.draft,
                context: categoryContext,
                cachedCategoryID: nil,
                cachedEmoji: nil
            )
            let remote = try await api.createRecipe(
                frameID: frameID,
                request: recipeRequest(
                    for: parsed.draft,
                    categoryID: classification.categoryID,
                    summary: classification.summary
                )
            )
            upsertNoteRecord(
                makeRecipeRecord(
                    noteID: parsed.note.id,
                    frameID: frameID,
                    contentHash: parsed.contentHash,
                    skylightID: remote.id,
                    noteModifiedAt: parsed.note.modificationDate,
                    remoteUpdatedAt: remote.attributes.updatedAt,
                    autoCategoryID: classification.autoCategoryID,
                    autoEmoji: classification.autoEmoji
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
        categoryContext: RecipeCategoryContext,
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
            // Emoji-insensitive: an auto-decorated Skylight title ("🥯 Bagels")
            // still adopts the plain note ("Bagels").
            let key = recipeTitleKey(parsed.draft.title)
            guard let index = candidates.firstIndex(where: {
                recipeTitleKey($0.attributes.summary ?? "") == key
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
                    categoryContext: categoryContext,
                    existingRecord: nil,
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
        categoryContext: RecipeCategoryContext,
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
                // One-time retrofit: recipes that predate on-device
                // classification get their category and title emoji on the
                // next sync even though their content is unchanged.
                guard await needsClassificationRetrofit(
                    record: record,
                    draft: parsed.draft,
                    context: categoryContext
                ) else { continue }
                summary.planned += 1
                guard !dryRun else { continue }
                try await pushRecipeUpdate(
                    parsed: parsed,
                    recipeID: record.skylightID,
                    frameID: frameID,
                    categoryContext: categoryContext,
                    existingRecord: record,
                    state: &state
                )
                summary.applied += 1
            case (true, false, _):
                summary.planned += 1
                guard !dryRun else { continue }
                try await pushRecipeUpdate(
                    parsed: parsed,
                    recipeID: record.skylightID,
                    frameID: frameID,
                    categoryContext: categoryContext,
                    existingRecord: record,
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
                        categoryContext: categoryContext,
                        existingRecord: record,
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
        categoryContext: RecipeCategoryContext,
        existingRecord: NoteSyncRecord?,
        state: inout SyncState
    ) async throws {
        let classification = await classifyRecipePush(
            draft: parsed.draft,
            context: categoryContext,
            cachedCategoryID: existingRecord?.autoCategoryID,
            cachedEmoji: existingRecord?.autoEmoji
        )
        let remote = try await api.updateRecipe(
            frameID: frameID,
            recipeID: recipeID,
            request: recipeRequest(
                for: parsed.draft,
                categoryID: classification.categoryID,
                summary: classification.summary
            )
        )
        upsertNoteRecord(
            makeRecipeRecord(
                noteID: parsed.note.id,
                frameID: frameID,
                contentHash: parsed.contentHash,
                skylightID: remote.id,
                noteModifiedAt: parsed.note.modificationDate,
                remoteUpdatedAt: remote.attributes.updatedAt,
                autoCategoryID: classification.autoCategoryID,
                autoEmoji: classification.autoEmoji
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
        remoteUpdatedAt: String?,
        autoCategoryID: String? = nil,
        autoEmoji: String? = nil
    ) -> NoteSyncRecord {
        NoteSyncRecord(
            kind: .recipes,
            frameID: frameID,
            appleNoteID: noteID,
            contentHash: contentHash,
            skylightID: skylightID,
            lastSyncedAt: now(),
            lastAppleModifiedAt: noteModifiedAt,
            lastSkylightUpdatedAt: remoteUpdatedAt,
            autoCategoryID: autoCategoryID,
            autoEmoji: autoEmoji
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
        // Keyed emoji-insensitively so a meal line like "Tacos" still matches
        // the auto-decorated recipe "🌮 Tacos".
        let recipesByTitle = try await api.listRecipes(frameID: frameID).reduce(into: [String: String]()) {
            result, recipe in
            let key = recipeTitleKey(recipe.attributes.summary ?? "")
            guard !key.isEmpty else { return }
            result[key] = recipe.id
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
                let matchedRecipeID = recipesByTitle[recipeTitleKey(meal.recipeTitle)]

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

    struct MealCategoryOption: Equatable, Sendable {
        let id: String
        let label: String
    }

    /// How recipe pushes choose their meal category. A configured category
    /// pins everything; Automatic classifies each recipe on device, falling
    /// back to the frame's first category when the model is unavailable.
    struct RecipeCategoryContext: Sendable {
        var fixedCategoryID: String?
        var fallbackCategoryID: String?
        var options: [MealCategoryOption] = []
        var isAutomatic: Bool { fixedCategoryID == nil }
    }

    private func resolveRecipeCategoryContext(
        selection: NotesSelection,
        frameID: String,
        needed: Bool
    ) async throws -> RecipeCategoryContext {
        guard needed else {
            return RecipeCategoryContext(fixedCategoryID: selection.destinationCategoryID)
        }
        let categories = try await api.listMealCategories(frameID: frameID)
        let options = categories.map {
            MealCategoryOption(id: $0.id, label: $0.attributes.label ?? "")
        }
        if let configured = selection.destinationCategoryID?.trimmed, !configured.isEmpty {
            guard categories.contains(where: { $0.id == configured }) else {
                throw SyncCoordinatorError.invalidMealCategory(selection.kind)
            }
            return RecipeCategoryContext(fixedCategoryID: configured, options: options)
        }
        guard let first = categories.first?.id else {
            throw SyncCoordinatorError.missingMealCategory(selection.kind)
        }
        return RecipeCategoryContext(fallbackCategoryID: first, options: options)
    }

    /// The category ID and Skylight summary for one recipe push, with the
    /// values to cache on its record. Classification runs at most once per
    /// recipe; cached results are reused on every later push.
    private struct RecipePushClassification {
        var categoryID: String?
        var summary: String
        var autoCategoryID: String?
        var autoEmoji: String?
    }

    private func classifyRecipePush(
        draft: RecipeDraft,
        context: RecipeCategoryContext,
        cachedCategoryID: String?,
        cachedEmoji: String?
    ) async -> RecipePushClassification {
        var categoryID = context.fixedCategoryID ?? cachedCategoryID
        var emoji = cachedEmoji
        let needsCategory = context.isAutomatic && categoryID == nil
        let needsEmoji = !draft.title.hasLeadingEmoji && emoji == nil

        if needsCategory || needsEmoji,
           let recipeClassifier,
           !context.options.isEmpty,
           await recipeClassifier.isAvailable,
           let result = await recipeClassifier.classify(
               title: draft.title,
               ingredients: draft.ingredients,
               categoryLabels: context.options.map(\.label)
           ) {
            if needsCategory {
                categoryID = context.options.first { $0.label == result.categoryLabel }?.id
            }
            if needsEmoji {
                emoji = result.emoji
            }
        }
        // A fallback assignment is a placeholder, not a classification: leave
        // the cache empty so the retrofit reclassifies once the model is back.
        var usedFallback = false
        if context.isAutomatic, categoryID == nil {
            categoryID = context.fallbackCategoryID
            usedFallback = true
        }

        let summary: String = if draft.title.hasLeadingEmoji || emoji == nil {
            draft.title
        } else {
            "\(emoji ?? "") \(draft.title)"
        }
        return RecipePushClassification(
            categoryID: categoryID,
            summary: summary,
            autoCategoryID: context.isAutomatic
                ? (usedFallback ? nil : categoryID)
                : cachedCategoryID,
            autoEmoji: emoji
        )
    }

    /// True when this record still needs its one-time automatic classification
    /// (category or title emoji) even though the note content is unchanged.
    private func needsClassificationRetrofit(
        record: NoteSyncRecord,
        draft: RecipeDraft,
        context: RecipeCategoryContext
    ) async -> Bool {
        guard context.isAutomatic, !context.options.isEmpty else { return false }
        let missingCategory = record.autoCategoryID == nil
        let missingEmoji = !draft.title.hasLeadingEmoji && record.autoEmoji == nil
        guard missingCategory || missingEmoji else { return false }
        guard let recipeClassifier else { return false }
        return await recipeClassifier.isAvailable
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
        categoryID: String?,
        summary: String? = nil
    ) -> SkylightRecipeRequest {
        // The description uses the same grammar the note formatter writes and the
        // parser reads, so pulled recipes round-trip without spurious changes.
        SkylightRecipeRequest(
            mealCategoryID: categoryID,
            summary: summary ?? draft.title,
            description: RecipeNoteFormatter.skylightDescription(for: draft),
            ingredients: draft.ingredients,
            url: draft.sourceURL
        )
    }

    /// Title key that ignores a leading emoji and case, so decorated Skylight
    /// summaries still match their plain Apple-side titles.
    private func recipeTitleKey(_ title: String) -> String {
        var stripped = title.trimmed
        while let first = stripped.first, first.isRecipeEmoji || first.isWhitespace {
            stripped.removeFirst()
        }
        return stripped.trimmed.lowercased()
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

    private static func choreLink(_ record: ChoreSyncRecord) -> ChoreSyncLink {
        ChoreSyncLink(
            appleID: record.appleReminderID,
            skylightID: record.skylightSeriesID,
            memberKey: record.memberKey,
            lastAppleModifiedAt: record.lastAppleModifiedAt,
            lastSkylightModifiedAt: record.lastSkylightModifiedAt,
            baselineTitle: record.lastSyncedTitle,
            baselineNotes: record.lastSyncedNotes,
            baselineRecurrence: record.lastSyncedRecurrence,
            baselineDueDate: record.baselineDueDate,
            baselineCompletedInstanceDate: record.baselineCompletedInstanceDate,
            recurrenceDegraded: record.recurrenceDegraded
        )
    }

    private static func choreRecord(
        mappingID: UUID,
        frameID: String,
        apple: ChoreReminderSnapshot,
        remote: SkylightChoreSnapshot,
        today: String
    ) -> ChoreSyncRecord {
        ChoreSyncRecord(
            mappingID: mappingID,
            frameID: frameID,
            appleReminderID: apple.id,
            skylightSeriesID: remote.id,
            memberKey: remote.memberKey,
            lastAppleModifiedAt: apple.modifiedAt,
            lastSkylightModifiedAt: remote.modifiedAt,
            contentFingerprint: choreFingerprint(snapshot: remote),
            lastSyncedTitle: remote.title,
            lastSyncedNotes: remote.notes,
            lastSyncedRecurrence: remote.recurrence.map(RecurrenceRuleConverter.format),
            baselineDueDate: apple.dueDate,
            baselineCompletedInstanceDate: remote.todayStatus == .complete || remote.todayStatus == .skipped
                ? today
                : nil,
            recurrenceDegraded: remote.recurrenceUnsupported || apple.recurrenceUnsupported
        )
    }

    private static func upsertChoreRecord(_ record: ChoreSyncRecord, state: inout SyncState) {
        state.chores.removeAll {
            $0.mappingID == record.mappingID &&
                ($0.appleReminderID == record.appleReminderID ||
                    $0.skylightSeriesID == record.skylightSeriesID)
        }
        state.chores.append(record)
    }

    private static func choreRequest(
        apple: ChoreReminderSnapshot,
        today: String,
        preserveRecurrence: Bool = false
    ) -> SkylightChoreRequest {
        let upForGrabs = apple.memberKey == ChoreMemberLink.upForGrabsKey
        return SkylightChoreRequest(
            summary: apple.title,
            description: apple.notes,
            start: apple.dueDate.map(isoDay) ?? today,
            startTime: apple.recurrence == nil ? apple.dueDate.map(choreTime) : nil,
            status: apple.isCompleted ? .complete : .pending,
            categoryID: upForGrabs ? nil : apple.memberKey,
            categoryIDs: upForGrabs ? [] : [apple.memberKey],
            recurring: preserveRecurrence ? nil : apple.recurrence != nil,
            recurrenceSet: preserveRecurrence
                ? nil
                : apple.recurrence.map { [skylightRecurrence($0, dueDate: apple.dueDate)] },
            upForGrabs: upForGrabs,
            routine: apple.recurrence != nil
        )
    }

    private static func choreMemberKey(
        _ resource: SkylightResource<SkylightChoreAttributes>,
        links: [ChoreMemberLink]
    ) -> String {
        if resource.attributes.upForGrabs == true {
            return ChoreMemberLink.upForGrabsKey
        }
        for relationshipName in ["categories", "category", "assignees"] {
            guard let data = resource.relationships?[relationshipName]?.data else { continue }
            switch data {
            case let .one(category): return category.id
            case let .many(categories):
                if let first = categories.first { return first.id }
            }
        }
        if let group = resource.attributes.group?.trimmed, !group.isEmpty,
           let match = links.first(where: {
               $0.memberKey == group ||
                   $0.memberLabel.localizedCaseInsensitiveCompare(group) == .orderedSame
           }) {
            return match.memberKey
        }
        return ""
    }

    private static func choreSeriesID(
        _ resource: SkylightResource<SkylightChoreAttributes>
    ) -> String {
        let series = resource.attributes.series?.trimmed ?? ""
        return series.isEmpty ? resource.id : series
    }

    private static func preferredChoreOccurrence(
        _ lhs: ChoreReminderSnapshot,
        _ rhs: ChoreReminderSnapshot
    ) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.id < rhs.id
        }
    }

    private static func choreRecurrence(
        _ recurrenceSet: [String]?
    ) -> (rule: ParsedRecurrenceRule?, unsupported: Bool) {
        guard let recurrenceSet, !recurrenceSet.isEmpty else { return (nil, false) }
        let ruleStrings = recurrenceSet.filter {
            let value = $0.trimmed.uppercased()
            return value.hasPrefix("RRULE:") || value.hasPrefix("FREQ=")
        }
        guard let first = ruleStrings.first else { return (nil, true) }
        do {
            let parsed = try RecurrenceRuleConverter.parse(first)
            return (
                parsed,
                ruleStrings.count != recurrenceSet.count ||
                    ruleStrings.count > 1 ||
                    !parsed.byHours.isEmpty
            )
        } catch {
            return (nil, true)
        }
    }

    private static func remoteSnapshot(
        _ resource: SkylightResource<SkylightChoreAttributes>,
        memberKey: String,
        status: SkylightChoreStatus?,
        modifiedAt: Date
    ) -> SkylightChoreSnapshot {
        let recurrence = choreRecurrence(resource.attributes.recurrenceSet)
        return SkylightChoreSnapshot(
            id: choreSeriesID(resource),
            title: resource.attributes.summary ?? "Untitled Chore",
            notes: resource.attributes.description,
            memberKey: memberKey,
            recurrenceRaw: resource.attributes.recurrenceSet ?? [],
            recurrence: recurrence.rule,
            recurrenceUnsupported: recurrence.unsupported,
            todayStatus: status,
            startDate: parseChoreDueDate(
                day: resource.attributes.start,
                time: resource.attributes.startTime,
                recurrence: recurrence.rule
            ),
            modifiedAt: modifiedAt
        )
    }

    private static func choreFingerprint(
        resource: SkylightResource<SkylightChoreAttributes>,
        memberKey: String,
        todayStatus: SkylightChoreStatus?
    ) -> String {
        let recurrence = resource.attributes.recurrenceSet?.joined(separator: "|") ?? ""
        return hash([
            resource.attributes.summary ?? "",
            resource.attributes.description ?? "",
            recurrence,
            memberKey,
            todayStatus?.rawValue ?? "",
            String(resource.attributes.upForGrabs ?? false)
        ].joined(separator: "\u{0}"))
    }

    private static func choreFingerprint(snapshot: SkylightChoreSnapshot) -> String {
        choreFingerprint(snapshot: snapshot, todayStatus: snapshot.todayStatus)
    }

    private static func choreFingerprint(
        snapshot: SkylightChoreSnapshot,
        todayStatus: SkylightChoreStatus?
    ) -> String {
        hash([
            snapshot.title,
            snapshot.notes ?? "",
            snapshot.recurrenceRaw.joined(separator: "|"),
            snapshot.memberKey,
            todayStatus?.rawValue ?? "",
            String(snapshot.memberKey == ChoreMemberLink.upForGrabsKey)
        ].joined(separator: "\u{0}"))
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func parseChoreDueDate(
        day: String?,
        time: String?,
        recurrence: ParsedRecurrenceRule? = nil
    ) -> Date? {
        guard let date = parseISODate(day) else { return nil }
        let parts = time?.split(separator: ":").compactMap { Int($0) } ?? []
        let hour = parts.first ?? recurrence?.byHours.first
        guard let hour else { return date }
        let minute = parts.count >= 2 ? parts[1] : 0
        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        )
    }

    private static func choreTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func skylightRecurrence(
        _ rule: ParsedRecurrenceRule,
        dueDate: Date?
    ) -> String {
        var rule = rule
        if rule.byHours.isEmpty {
            let hour = dueDate.map { Calendar.current.component(.hour, from: $0) } ?? 6
            rule.byHours = [nearestSkylightChoreHour(hour)]
        } else if rule.byHours.count > 1 || ![6, 14, 20].contains(rule.byHours[0]) {
            rule.byHours = [nearestSkylightChoreHour(rule.byHours[0])]
        }
        return "RRULE:\(RecurrenceRuleConverter.format(rule))"
    }

    private static func nearestSkylightChoreHour(_ hour: Int) -> Int {
        [6, 14, 20].min { abs($0 - hour) < abs($1 - hour) } ?? 6
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

    private func upsertReminderListRecord(
        _ record: ReminderListSyncRecord,
        in state: inout SyncState
    ) {
        state.reminderLists.removeAll {
            $0.mappingID == record.mappingID && $0.frameID == record.frameID
        }
        state.reminderLists.append(record)
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
    let attributes: SkylightListAttributes?
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
