import CoreGraphics
import Foundation
import Testing
@testable import SkylightBridge

@MainActor
struct SyncCoordinatorTests {
    @Test("A fresh configuration is safely opt-in")
    func freshConfigurationDoesNothing() async throws {
        let api = CoordinatorAPIStub()
        let coordinator = makeCoordinator(api: api, reminders: [])

        let summary = try await coordinator.sync(configuration: .empty)

        #expect(summary.totalPlanned == 0)
        #expect(summary.totalApplied == 0)
        #expect(await api.snapshot() == .init())
    }

    @Test("A reminder destination is planned without writes during dry run")
    func reminderDryRunPlansDestinationAndSelectedItem() async throws {
        let api = CoordinatorAPIStub()
        let reminders = [
            reminder(id: "selected", title: "Milk"),
            reminder(id: "excluded", title: "Bread")
        ]
        let coordinator = makeCoordinator(api: api, reminders: reminders)
        var configuration = configuredReminders(dryRun: true)
        configuration.reminderMappings[0].selectionMode = .selectedItems
        configuration.reminderMappings[0].selectedReminderIDs = ["selected"]

        let summary = try await coordinator.sync(configuration: configuration)
        let calls = await api.snapshot()

        #expect(summary.reminders.planned == 2)
        #expect(summary.reminders.applied == 0)
        #expect(calls.listCollections == 1)
        #expect(calls.createdLists == 0)
        #expect(calls.createdItems == 0)
    }

    @Test("A new photo album and its first photo are planned without writes during dry run")
    func photoDryRunPlansNewAlbumAndPhoto() async throws {
        let api = CoordinatorAPIStub()
        let photoSource = CoordinatorPhotoSource(assets: [photoAsset(id: "apple-photo")])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: photoSource,
            imageConverter: CoordinatorImageConverter(convertedAssetID: "apple-photo")
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = true
        configuration.photoMappings = [
            PhotoMapping(
                name: "Our House",
                sourceCollectionID: "apple-album",
                sourceCollectionTitle: "Our House",
                destinationAlbumTitle: "Our House"
            )
        ]

        let summary = try await coordinator.sync(configuration: configuration)
        let calls = await api.snapshot()

        #expect(summary.photos.planned == 2)
        #expect(summary.photos.applied == 0)
        #expect(calls.albumCollections == 1)
        #expect(calls.createdAlbums == 0)
    }

    @Test("A live reminder sync creates its named list and only selected items")
    func reminderLiveSyncCreatesDestinationAndSelectedItem() async throws {
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore()
        let reminders = [
            reminder(id: "selected", title: "Milk"),
            reminder(id: "excluded", title: "Bread")
        ]
        let coordinator = makeCoordinator(api: api, reminders: reminders, state: state)
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].selectionMode = .selectedItems
        configuration.reminderMappings[0].selectedReminderIDs = ["selected"]

        let summary = try await coordinator.sync(configuration: configuration)
        let calls = await api.snapshot()
        let persisted = try await state.loadSyncState()

        #expect(summary.reminders.planned == 2)
        #expect(summary.reminders.applied == 2)
        #expect(calls.createdLists == 1)
        #expect(calls.createdItems == 1)
        #expect(persisted.reminders.map(\.appleReminderID) == ["selected"])
        #expect(await state.saveCount > 0)
    }

    private func makeCoordinator(
        api: CoordinatorAPIStub,
        reminders: [AppleReminderSnapshot],
        photoSource: CoordinatorPhotoSource = CoordinatorPhotoSource(),
        imageConverter: CoordinatorImageConverter = CoordinatorImageConverter(),
        state: CoordinatorStateStore = CoordinatorStateStore()
    ) -> SyncCoordinator {
        SyncCoordinator(
            photoSource: photoSource,
            reminderSource: CoordinatorReminderSource(reminders: reminders),
            notesSource: CoordinatorNotesSource(),
            imageConverter: imageConverter,
            api: api,
            stateStore: state
        )
    }

    private func configuredReminders(dryRun: Bool) -> AppConfiguration {
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = dryRun
        configuration.reminderMappings = [
            ReminderListMapping(
                sourceListID: "apple-list",
                sourceListTitle: "Groceries",
                destinationListTitle: "Groceries",
                destinationKind: .shopping,
                direction: .appleToSkylight,
                enabled: true
            )
        ]
        return configuration
    }

    private func reminder(id: String, title: String) -> AppleReminderSnapshot {
        AppleReminderSnapshot(
            id: id,
            externalID: nil,
            listID: "apple-list",
            listTitle: "Groceries",
            title: title,
            notes: nil,
            url: nil,
            isCompleted: false,
            completionDate: nil,
            startDateComponents: nil,
            dueDateComponents: nil,
            priority: 0,
            creationDate: Date(timeIntervalSince1970: 100),
            modificationDate: Date(timeIntervalSince1970: 200),
            hasRecurrenceRules: false
        )
    }

    private func photoAsset(id: String) -> ApplePhotoAssetSnapshot {
        ApplePhotoAssetSnapshot(
            id: id,
            mediaKind: .image,
            pixelWidth: 1,
            pixelHeight: 1,
            creationDate: nil,
            modificationDate: nil,
            adjustmentDate: nil,
            contentTypeIdentifier: "public.jpeg",
            isFavorite: false,
            isHidden: false,
            hasAdjustments: false
        )
    }
}

private enum CoordinatorStubError: Error {
    case unexpectedCall
}

@MainActor
private final class CoordinatorPhotoSource: PhotoSyncSource {
    let assets: [ApplePhotoAssetSnapshot]

    init(assets: [ApplePhotoAssetSnapshot] = []) {
        self.assets = assets
    }

    func syncPhotoCollections() async throws -> [ApplePhotoCollectionSnapshot] { [] }
    func syncPhotoAssets(in collectionID: String) async throws -> [ApplePhotoAssetSnapshot] { assets }
    func syncPhotoAssets(withIDs assetIDs: [String]) async throws -> [ApplePhotoAssetSnapshot] { [] }
    func syncRenderedPhoto(withID assetID: String, maximumLongEdge: Int) async throws -> AppleRenderedPhoto {
        guard let asset = assets.first(where: { $0.id == assetID }),
              let context = CGContext(
                  data: nil,
                  width: 1,
                  height: 1,
                  bitsPerComponent: 8,
                  bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage() else {
            throw CoordinatorStubError.unexpectedCall
        }
        return AppleRenderedPhoto(asset: asset, image: image)
    }
}

@MainActor
private final class CoordinatorReminderSource: ReminderSyncSource {
    let reminders: [AppleReminderSnapshot]

    init(reminders: [AppleReminderSnapshot]) {
        self.reminders = reminders
    }

    func syncReminders(in listID: String) async throws -> [AppleReminderSnapshot] { reminders }
    func syncCreateReminder(in listID: String, draft: AppleReminderDraft) async throws -> AppleReminderSnapshot {
        throw CoordinatorStubError.unexpectedCall
    }
    func syncUpdateReminder(withID reminderID: String, patch: AppleReminderPatch) async throws -> AppleReminderSnapshot {
        throw CoordinatorStubError.unexpectedCall
    }
    func syncRemoveReminder(withID reminderID: String) async throws {
        throw CoordinatorStubError.unexpectedCall
    }
}

private actor CoordinatorNotesSource: NotesSyncSource {
    func syncNoteSummaries(inFolderID folderID: String) async throws -> [AppleNoteSummarySnapshot] { [] }
    func syncNote(withID noteID: String, inFolderID folderID: String) async throws -> AppleNoteSnapshot {
        throw CoordinatorStubError.unexpectedCall
    }
}

private actor CoordinatorImageConverter: SyncImageConverting {
    let convertedAssetID: String?

    init(convertedAssetID: String? = nil) {
        self.convertedAssetID = convertedAssetID
    }

    func syncConvert(
        _ renderedPhoto: AppleRenderedPhoto,
        options: AppleImageConversionOptions
    ) async throws -> AppleConvertedImage {
        guard let convertedAssetID else {
            throw CoordinatorStubError.unexpectedCall
        }
        return AppleConvertedImage(
            assetID: convertedAssetID,
            data: Data([0x01]),
            typeIdentifier: "public.jpeg",
            pixelWidth: 1,
            pixelHeight: 1,
            sha256: "rendered-hash"
        )
    }
}

private actor CoordinatorStateStore: SyncStatePersisting {
    private var state = SyncState()
    private(set) var saveCount = 0

    func loadSyncState() async throws -> SyncState { state }
    func saveSyncState(_ state: SyncState) async throws {
        self.state = state
        saveCount += 1
    }
}

private struct CoordinatorAPICalls: Equatable, Sendable {
    var listCollections = 0
    var createdLists = 0
    var createdItems = 0
    var albumCollections = 0
    var createdAlbums = 0
}

private actor CoordinatorAPIStub: SkylightSyncAPI {
    private var calls = CoordinatorAPICalls()

    func snapshot() -> CoordinatorAPICalls { calls }

    func listLists(frameID: String) async throws -> SkylightListCollectionResponse {
        calls.listCollections += 1
        return SkylightListCollectionResponse(data: [], included: nil)
    }

    func createList(
        frameID: String,
        request: SkylightListRequest
    ) async throws -> SkylightResource<SkylightListAttributes> {
        calls.createdLists += 1
        return SkylightResource(
            id: "remote-list",
            attributes: SkylightListAttributes(
                label: request.label,
                color: request.color,
                kind: request.kind,
                hideOnDevice: request.hideOnDevice
            )
        )
    }

    func listListItems(
        frameID: String,
        listID: String
    ) async throws -> [SkylightResource<SkylightListItemAttributes>] { [] }

    func createListItem(
        frameID: String,
        listID: String,
        request: SkylightListItemRequest
    ) async throws -> SkylightResource<SkylightListItemAttributes> {
        calls.createdItems += 1
        return SkylightResource(
            id: "remote-item-\(calls.createdItems)",
            attributes: SkylightListItemAttributes(
                label: request.label,
                status: request.status,
                section: request.section,
                position: request.position
            )
        )
    }

    func updateListItem(frameID: String, listID: String, itemID: String, request: SkylightListItemRequest) async throws -> SkylightResource<SkylightListItemAttributes> { throw CoordinatorStubError.unexpectedCall }
    func deleteListItem(frameID: String, listID: String, itemID: String) async throws { throw CoordinatorStubError.unexpectedCall }
    func listAlbums(frameID: String) async throws -> [SkylightResource<SkylightAlbumAttributes>] {
        calls.albumCollections += 1
        return []
    }
    func createAlbum(frameID: String, title: String) async throws -> SkylightResource<SkylightAlbumAttributes> {
        calls.createdAlbums += 1
        throw CoordinatorStubError.unexpectedCall
    }
    func requestUploadURL(ext: String, frameIDs: [String], caption: String?) async throws -> SkylightUploadURLAttributes { throw CoordinatorStubError.unexpectedCall }
    func upload(data: Data, to presignedURL: URL, contentType: String) async throws { throw CoordinatorStubError.unexpectedCall }
    func addMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws { throw CoordinatorStubError.unexpectedCall }
    func removeMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws { throw CoordinatorStubError.unexpectedCall }
    func deleteMessage(frameID: String, messageID: String) async throws { throw CoordinatorStubError.unexpectedCall }
    func getMessage(frameID: String, messageID: String) async throws -> SkylightResource<SkylightPhotoMessageAttributes> { throw CoordinatorStubError.unexpectedCall }
    func listMessages(frameID: String, page: Int?, syncToken: String?, pageToken: String?) async throws -> SkylightPhotoMessagesResponse { throw CoordinatorStubError.unexpectedCall }
    func createRecipe(frameID: String, request: SkylightRecipeRequest) async throws -> SkylightResource<SkylightRecipeAttributes> { throw CoordinatorStubError.unexpectedCall }
    func updateRecipe(frameID: String, recipeID: String, request: SkylightRecipeRequest) async throws -> SkylightResource<SkylightRecipeAttributes> { throw CoordinatorStubError.unexpectedCall }
    func listRecipes(frameID: String) async throws -> [SkylightResource<SkylightRecipeAttributes>] { [] }
    func deleteRecipe(frameID: String, recipeID: String, applyToSittings: Bool) async throws { throw CoordinatorStubError.unexpectedCall }
    func listMealCategories(frameID: String) async throws -> [SkylightResource<SkylightMealCategoryAttributes>] { [] }
    func createMealSitting(frameID: String, request: SkylightMealSittingRequest) async throws -> SkylightResource<SkylightMealSittingAttributes> { throw CoordinatorStubError.unexpectedCall }
    func updateMealInstance(frameID: String, mealID: String, instanceISO: String, request: SkylightMealInstanceUpdateRequest) async throws -> SkylightResource<SkylightMealSittingAttributes> { throw CoordinatorStubError.unexpectedCall }
    func deleteMealInstance(frameID: String, mealID: String, instanceISO: String, applyTo: String?) async throws { throw CoordinatorStubError.unexpectedCall }
}
