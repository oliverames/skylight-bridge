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
    case missingNotesFolder(NotesContentKind)
    case invalidUploadURL(String)
    case missingUploadMessageID
    case convertedImageTooLarge(assetID: String, bytes: Int)
    case photoProcessingTimedOut(String)
    case photoProcessingFailed(messageID: String, status: String)
    case unsupportedMealDay(String)
    case invalidMealReference(String)
    case missingReminderDestination(UUID)
    case missingMealCategory(NotesContentKind)

    var errorDescription: String? {
        switch self {
        case .missingFrameID:
            "A Skylight frame must be selected before synchronization."
        case let .missingPhotoCollection(mappingID):
            "Photo mapping \(mappingID) does not have a usable source collection."
        case let .missingPhotoDestination(mappingID):
            "Photo mapping \(mappingID) does not have a usable destination album."
        case let .missingNotesFolder(kind):
            "The enabled \(kind.rawValue) selection does not have an Apple Notes folder."
        case let .invalidUploadURL(value):
            "Skylight returned an invalid upload URL: \(value)"
        case .missingUploadMessageID:
            "Skylight did not return a message identifier for the photo upload."
        case let .convertedImageTooLarge(assetID, bytes):
            "Converted photo \(assetID) is \(bytes) bytes, above the 25 MB upload limit."
        case let .photoProcessingTimedOut(messageID):
            "Skylight did not finish processing uploaded photo \(messageID) in time."
        case let .photoProcessingFailed(messageID, status):
            "Skylight could not process uploaded photo \(messageID): \(status)."
        case let .unsupportedMealDay(day):
            "The meal day '\(day)' is not an ISO date or weekday name."
        case let .invalidMealReference(value):
            "The stored meal reference is invalid: \(value)"
        case let .missingReminderDestination(mappingID):
            "Reminder mapping \(mappingID) does not have a Skylight list name or ID."
        case let .missingMealCategory(kind):
            "Skylight does not have a meal category available for \(kind.rawValue)."
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

    private func syncPhotos(
        mappings: [PhotoMapping],
        frameID: String,
        dryRun: Bool,
        state: inout SyncState
    ) async throws -> SyncDomainSummary {
        var summary = SyncDomainSummary()

        for mapping in mappings {
            let sourceAssets = try await photoAssets(for: mapping)
                .filter { $0.mediaKind == .image || $0.mediaKind == .livePhoto }
            var convertedByID: [String: AppleConvertedImage] = [:]

            for asset in sourceAssets.sorted(by: { $0.id < $1.id }) {
                let rendered = try await photoSource.syncRenderedPhoto(
                    withID: asset.id,
                    maximumLongEdge: mapping.maximumLongEdge
                )
                convertedByID[asset.id] = try await imageConverter.syncConvert(
                    rendered,
                    options: AppleImageConversionOptions(
                        maximumLongEdge: mapping.maximumLongEdge,
                        jpegQuality: mapping.jpegQuality
                    )
                )
            }

            let mappingRecords = state.photos.filter { $0.mappingID == mapping.id }
            let plannerAssets = convertedByID.values.map {
                PhotoAssetSnapshot(id: $0.assetID, renderedHash: $0.sha256)
            }
            let links = mappingRecords.map {
                ManagedPhotoLink(
                    appleAssetID: $0.appleAssetID,
                    renderedHash: $0.renderedHash,
                    skylightPhotoID: $0.skylightMessageID
                )
            }
            let plannedActions = PhotoSyncPlanner.plan(assets: plannerAssets, managedLinks: links)
            let actions = plannedActions.filter { action in
                if case .deleteManaged = action {
                    return mapping.removalPolicy == .removeFromSkylight
                }
                return true
            }

            let currentAssetIDs = Set(convertedByID.keys)
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
                }
            }

            if let destinationID = destination.id {
                for record in mappingRecords where currentAssetIDs.contains(record.appleAssetID) {
                    let oldAlbumIDs = record.skylightAlbumIDs.subtracting([destinationID])
                    let needsAdd = !record.skylightAlbumIDs.contains(destinationID)
                    if needsAdd {
                        summary.planned += 1
                    }
                    if !oldAlbumIDs.isEmpty {
                        summary.planned += 1
                    }

                    guard !dryRun, needsAdd || !oldAlbumIDs.isEmpty else { continue }
                    if needsAdd {
                        try await api.addMessages(
                            frameID: frameID,
                            albumIDs: [destinationID],
                            messageIDs: [record.skylightMessageID]
                        )
                        summary.applied += 1
                    }
                    if !oldAlbumIDs.isEmpty {
                        try await api.removeMessages(
                            frameID: frameID,
                            albumIDs: oldAlbumIDs.sorted(),
                            messageIDs: [record.skylightMessageID]
                        )
                        summary.applied += 1
                    }
                    upsertPhotoRecord(
                        PhotoSyncRecord(
                            mappingID: record.mappingID,
                            appleAssetID: record.appleAssetID,
                            renderedHash: record.renderedHash,
                            skylightMessageID: record.skylightMessageID,
                            skylightAlbumIDs: [destinationID],
                            lastSyncedAt: now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)
                }
            }

            summary.planned += actions.count
            guard !dryRun else { continue }

            for action in actions {
                switch action {
                case let .upload(assetID, replacingRemoteID):
                    guard let destinationID = destination.id else {
                        throw SyncCoordinatorError.missingPhotoDestination(mapping.id)
                    }
                    guard let converted = convertedByID[assetID] else { continue }

                    let newMessageID = try await uploadPhoto(
                        converted,
                        frameID: frameID,
                        destinationAlbumID: destinationID
                    )
                    upsertPhotoRecord(
                        PhotoSyncRecord(
                            mappingID: mapping.id,
                            appleAssetID: assetID,
                            renderedHash: converted.sha256,
                            skylightMessageID: newMessageID,
                            skylightAlbumIDs: [destinationID],
                            lastSyncedAt: now()
                        ),
                        in: &state
                    )
                    try await checkpoint(state, dryRun: dryRun)
                    if let replacingRemoteID,
                       let previous = mappingRecords.first(where: {
                           $0.skylightMessageID == replacingRemoteID
                       }) {
                        if !previous.skylightAlbumIDs.isEmpty {
                            try await api.removeMessages(
                                frameID: frameID,
                                albumIDs: previous.skylightAlbumIDs.sorted(),
                                messageIDs: [replacingRemoteID]
                            )
                        }
                        try await api.deleteMessage(frameID: frameID, messageID: replacingRemoteID)
                    }
                    summary.applied += 1

                case let .deleteManaged(remoteID):
                    guard let record = state.photos.first(where: {
                        $0.mappingID == mapping.id && $0.skylightMessageID == remoteID
                    }) else { continue }
                    if !record.skylightAlbumIDs.isEmpty {
                        try await api.removeMessages(
                            frameID: frameID,
                            albumIDs: record.skylightAlbumIDs.sorted(),
                            messageIDs: [remoteID]
                        )
                    }
                    try await api.deleteMessage(frameID: frameID, messageID: remoteID)
                    state.photos.removeAll { $0.id == record.id }
                    try await checkpoint(state, dryRun: dryRun)
                    summary.applied += 1
                }
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
        if let albumID = mapping.destinationAlbumID, !albumID.isEmpty {
            return PhotoDestinationResolution(id: albumID, needsCreation: false)
        }

        let title = mapping.destinationAlbumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw SyncCoordinatorError.missingPhotoDestination(mapping.id)
        }
        let albums = try await api.listAlbums(frameID: frameID)
        if let existing = albums.first(where: {
            $0.attributes.title?.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
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
        guard let uploadURL = URL(string: upload.url) else {
            throw SyncCoordinatorError.invalidUploadURL(upload.url)
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
            var records = state.reminders.filter { $0.mappingID == mapping.id }
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
            if mapping.selectionMode == .everything {
                let matched = initialReminderMatches(
                    mapping: mapping,
                    apple: selectedApple,
                    remote: selectedRemoteResources,
                    existing: records,
                    syncTime: syncTime
                )
                for record in matched {
                    records.append(record)
                    if !dryRun {
                        upsertReminderRecord(record, in: &state)
                        try await checkpoint(state, dryRun: dryRun)
                    }
                }
            }
            let links = records.map {
                ReminderSyncLink(
                    appleID: $0.appleReminderID,
                    skylightID: $0.skylightItemID,
                    lastAppleModifiedAt: $0.lastAppleModifiedAt,
                    lastSkylightModifiedAt: $0.lastSkylightModifiedAt
                )
            }
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

            let appleByID = Dictionary(uniqueKeysWithValues: selectedApple.map { ($0.id, $0) })
            let remoteByID = Dictionary(uniqueKeysWithValues: selectedRemoteResources.map { ($0.id, $0) })
            let remoteSnapshotByID = Dictionary(uniqueKeysWithValues: remoteSnapshots.map { ($0.id, $0) })

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
                            apple: apple,
                            remoteID: remoteID,
                            remoteModifiedAt: remoteSnapshotByID[remoteID]?.modifiedAt ?? now()
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
                        $0.mappingID == mapping.id && $0.skylightItemID == remoteID
                    }
                    try await checkpoint(state, dryRun: dryRun)

                case let .deleteApple(appleID):
                    try await reminderSource.syncRemoveReminder(withID: appleID)
                    state.reminders.removeAll {
                        $0.mappingID == mapping.id && $0.appleReminderID == appleID
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
        let configuredID = mapping.destinationListID.trimmed
        if !configuredID.isEmpty {
            return ReminderDestinationResolution(id: configuredID, needsCreation: false)
        }
        let title = mapping.destinationListTitle.trimmed
        guard !title.isEmpty else {
            throw SyncCoordinatorError.missingReminderDestination(mapping.id)
        }
        let lists = try await api.listLists(frameID: frameID).data
        if let existing = lists.first(where: {
            $0.attributes.label?.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
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

    private func syncRecipes(
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
        var summary = SyncDomainSummary()

        for note in notes {
            let draft = try RecipeParser.parse(note.plaintext)
            let contentHash = stableHash(note.plaintext)
            let existing = state.notes.first {
                $0.kind == .recipes && $0.appleNoteID == note.id
            }
            guard existing?.contentHash != contentHash else { continue }

            summary.planned += 1
            guard !dryRun else { continue }
            let request = recipeRequest(for: draft, categoryID: mealCategoryID)
            let remote: SkylightResource<SkylightRecipeAttributes>
            if let existing {
                remote = try await api.updateRecipe(
                    frameID: frameID,
                    recipeID: existing.skylightID,
                    request: request
                )
            } else {
                remote = try await api.createRecipe(frameID: frameID, request: request)
            }
            upsertNoteRecord(
                NoteSyncRecord(
                    kind: .recipes,
                    appleNoteID: note.id,
                    contentHash: contentHash,
                    skylightID: remote.id,
                    lastSyncedAt: now()
                ),
                in: &state
            )
            try await checkpoint(state, dryRun: dryRun)
            summary.applied += 1
        }

        let desiredNoteIDs = Set(try await selectedNoteSummaries(for: selection).map(\.id))
        let removedRecords = state.notes.filter {
            $0.kind == .recipes && !desiredNoteIDs.contains($0.appleNoteID)
        }
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
            for meal in MealPlanParser.parse(note.plaintext) {
                let date = try mealDateResolver.resolveMealDate(meal.day, relativeTo: now())
                let slot = mealSlotKey(noteID: note.id, meal: meal, occurrences: &occurrences)
                let contentHash = stableHash(
                    [date, meal.category, meal.recipeTitle].joined(separator: "\u{0}")
                )
                let existing = state.notes.first {
                    $0.kind == .meals && $0.appleNoteID == slot
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

        let parsedSlots = desiredMealSlots(notes: notes)
        let protectedNoteIDs = Set(
            try await selectedNoteSummaries(for: selection)
                .filter(\.isPasswordProtected)
                .map(\.id)
        )
        let removedRecords = state.notes.filter {
            guard $0.kind == .meals, !parsedSlots.contains($0.appleNoteID) else { return false }
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

    private func desiredMealSlots(notes: [AppleNoteSnapshot]) -> Set<String> {
        var result: Set<String> = []
        for note in notes {
            var occurrences: [String: Int] = [:]
            for meal in MealPlanParser.parse(note.plaintext) {
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
        if let configured = selection.destinationCategoryID?.trimmed, !configured.isEmpty {
            return configured
        }
        guard let categoryID = try await api.listMealCategories(frameID: frameID).first?.id else {
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
        var descriptionSections: [String] = []
        if let description = draft.description, !description.isEmpty {
            descriptionSections.append(description)
        }
        let details = [
            draft.servings.map { "Servings: \($0)" },
            draft.preparationTime.map { "Prep: \($0)" },
            draft.cookingTime.map { "Cook: \($0)" }
        ].compactMap { $0 }
        if !details.isEmpty {
            descriptionSections.append(details.joined(separator: "\n"))
        }
        if !draft.ingredients.isEmpty {
            descriptionSections.append("Ingredients\n" + draft.ingredients.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !draft.instructions.isEmpty {
            let instructions = draft.instructions.enumerated().map { index, instruction in
                "\(index + 1). \(instruction)"
            }
            descriptionSections.append("Instructions\n" + instructions.joined(separator: "\n"))
        }
        if !draft.tags.isEmpty {
            descriptionSections.append("Tags: " + draft.tags.joined(separator: ", "))
        }

        return SkylightRecipeRequest(
            mealCategoryID: categoryID,
            summary: draft.title,
            description: descriptionSections.isEmpty
                ? nil
                : descriptionSections.joined(separator: "\n\n"),
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
        apple: AppleReminderSnapshot,
        remoteID: String,
        remoteModifiedAt: Date
    ) -> ReminderSyncRecord {
        ReminderSyncRecord(
            mappingID: mapping.id,
            appleReminderID: apple.id,
            appleExternalID: apple.externalID,
            skylightItemID: remoteID,
            lastAppleModifiedAt: apple.modificationDate ?? apple.creationDate ?? .distantPast,
            lastSkylightModifiedAt: remoteModifiedAt,
            contentFingerprint: reminderFingerprint(
                title: apple.title,
                isCompleted: apple.isCompleted
            )
        )
    }

    private func initialReminderMatches(
        mapping: ReminderListMapping,
        apple: [AppleReminderSnapshot],
        remote: [SkylightResource<SkylightListItemAttributes>],
        existing: [ReminderSyncRecord],
        syncTime: Date
    ) -> [ReminderSyncRecord] {
        let linkedAppleIDs = Set(existing.map(\.appleReminderID))
        var availableRemote = remote.filter {
            !existing.map(\.skylightItemID).contains($0.id)
        }
        var matches: [ReminderSyncRecord] = []

        for appleItem in apple.sorted(by: { $0.id < $1.id })
        where !linkedAppleIDs.contains(appleItem.id) {
            let fingerprint = reminderFingerprint(
                title: appleItem.title,
                isCompleted: appleItem.isCompleted
            )
            guard let index = availableRemote.firstIndex(where: {
                reminderFingerprint(
                    title: $0.attributes.label ?? "",
                    isCompleted: $0.attributes.status == .completed
                ) == fingerprint
            }) else { continue }
            let remoteItem = availableRemote.remove(at: index)
            matches.append(
                reminderRecord(
                    mapping: mapping,
                    apple: appleItem,
                    remoteID: remoteItem.id,
                    remoteModifiedAt: syncTime
                )
            )
        }
        return matches
    }

    private func reminderFingerprint(title: String, isCompleted: Bool) -> String {
        stableHash("\(title)\u{0}\(isCompleted)")
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
