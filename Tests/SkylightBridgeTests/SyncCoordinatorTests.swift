import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import SkylightBridge

@MainActor
struct SyncCoordinatorTests {
    @Test("Adopted reminder completion follows direction and policy across retries",
          arguments: [ReminderSyncDirection.appleToSkylight, .skylightToApple, .twoWay],
          [SyncConflictPolicy.appleWins, .skylightWins])
    func adoptedReminderCompletionIsReconciled(direction: ReminderSyncDirection, policy: SyncConflictPolicy) async throws {
        let api = CoordinatorAPIStub()
        await api.allowListItemUpdates()
        await api.configureLists([remoteReminderList()], items: [SkylightResource(
            id: "remote-item", attributes: SkylightListItemAttributes(
                label: "Milk", status: .completed, section: nil, position: nil
            )
        )])
        let source = CoordinatorReminderSource(reminders: [reminder(id: "apple-item", title: "Milk")], allowsUpdate: true)
        let state = CoordinatorStateStore()
        let coordinator = makeCoordinator(api: api, reminders: [], state: state, reminderSource: source)
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = direction
        configuration.reminderMappings[0].conflictPolicy = policy
        let first = try await coordinator.sync(configuration: configuration)
        let second = try await coordinator.sync(configuration: configuration)
        let appleWins = direction == .appleToSkylight || (direction == .twoWay && policy == .appleWins)
        let remote = try await api.listListItems(frameID: "frame-1", listID: "remote-list")
        #expect(remote.first?.attributes.status == (appleWins ? .pending : .completed))
        #expect(source.updatedReminders.count == (appleWins ? 0 : 1))
        #expect(first.reminders.applied == 1)
        #expect(second.reminders.applied == 0)
        #expect(try await state.loadSyncState().reminders.count == 1)
        #expect(await api.snapshot().createdItems == 0)
    }

    @Test("Recipe cleanup accepts confirmed absence", arguments: [404, 410])
    func recipeCleanupAcceptsAbsence(status: Int) async throws {
        let api = CoordinatorAPIStub()
        await api.configureCleanupError(SkylightAPIError.httpStatus(code: status, endpoint: "/recipes/old", body: ""))
        var original = SyncState()
        original.notes = [recipeSyncRecord(noteID: "gone", contentHash: "old", skylightID: "old", remoteRevision: "old")]
        let state = CoordinatorStateStore(state: original)
        var configuration = configuredRecipes()
        configuration.recipeSelection.direction = .appleToSkylight
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)
        _ = try await coordinator.sync(configuration: configuration)
        #expect(try await state.loadSyncState().notes.isEmpty)
    }

    @Test("Meal replacement retries deletion without recreating its replacement")
    func mealReplacementKeepsCleanupIdentity() async throws {
        let api = CoordinatorAPIStub()
        await api.configureMealCategories(mealCategories)
        let source = CoordinatorNotesSource(notes: [recipeNote(id: "plan", plaintext: "Wednesday Dinner: Soup")])
        let state = CoordinatorStateStore()
        let coordinator = makeCoordinator(api: api, reminders: [], state: state, notesSource: source,
                                          now: { Date(timeIntervalSince1970: 1_784_131_200) })
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.mealSelection.folderID = "folder-1"
        configuration.mealSelection.enabled = true
        _ = try await coordinator.sync(configuration: configuration)
        let nextCoordinator = makeCoordinator(api: api, reminders: [], state: state, notesSource: source,
                                              now: { Date(timeIntervalSince1970: 1_784_736_000) })
        await api.configureCleanupError(URLError(.timedOut))
        do {
            _ = try await nextCoordinator.sync(configuration: configuration)
            Issue.record("Expected failed old-meal cleanup")
        } catch {}
        let failedState = try await state.loadSyncState()
        #expect(failedState.pendingMealCleanups.count == 1)
        #expect(await api.createdMealCount == 2)
        try await state.saveSyncState(JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(failedState)))
        await api.configureCleanupError(nil)
        _ = try await nextCoordinator.sync(configuration: configuration)
        #expect(await api.createdMealCount == 2)
        #expect(await api.deletedMealIDs == ["meal-1"])
        #expect(try await state.loadSyncState().pendingMealCleanups.isEmpty)
    }

    @Test("An oversized remote recipe cannot overwrite the original Apple note")
    func oversizedRecipeLeavesNoteIntact() async throws {
        let api = CoordinatorAPIStub()
        await api.configureMealCategories(mealCategories)
        let source = CoordinatorNotesSource(notes: [recipeNote(id: "note-1", plaintext: "Soup\nKeep this instruction.")])
        await api.configureRecipes([SkylightResource(id: "remote-1", attributes: SkylightRecipeAttributes(
            summary: "Soup", description: String(repeating: "x", count: 4_097),
            ingredients: ["Stock"], url: nil, imageURL: nil, createdAt: nil, updatedAt: "rev-2"
        ))])
        var configuration = configuredRecipes()
        configuration.recipeSelection.conflictPolicy = .skylightWins
        let coordinator = makeCoordinator(api: api, reminders: [], notesSource: source)
        do {
            _ = try await coordinator.sync(configuration: configuration)
            Issue.record("Expected remote recipe parsing to fail")
        } catch RecipeParserError.fieldTooLong {
            // Expected: no Notes write may follow the parser limit.
        }
        #expect(await source.updatedBodiesByNoteID.isEmpty)
        #expect(await source.createdBodies.isEmpty)
        #expect(try await source.syncNote(withID: "note-1", inFolderID: "folder-1").plaintext == "Soup\nKeep this instruction.")
    }

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

    @Test("Returning to a frame reuses its recorded photo album after a rename")
    func photoDestinationUsesFrameScopedState() async throws {
        let mappingID = UUID()
        let asset = photoAsset(id: "apple-photo")
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-frame-1",
                attributes: SkylightAlbumAttributes(
                    title: "Renamed on Skylight",
                    messageCount: 1,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        ])
        var initial = SyncState()
        initial.photos = [PhotoSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            destinationAlbumID: "album-frame-1",
            appleAssetID: asset.id,
            renderedHash: "rendered-hash",
            skylightMessageID: "message-1",
            skylightAlbumIDs: ["album-frame-1"],
            lastSyncedAt: Date(timeIntervalSince1970: 100)
        )]
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(assets: [asset]),
            imageConverter: CoordinatorImageConverter(convertedAssetID: asset.id),
            state: state
        )
        var mapping = PhotoMapping(
            name: "Family",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Family",
            destinationAlbumTitle: "Original Album Name"
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        #expect(await api.snapshot().createdAlbums == 0)
        #expect(await api.uploadCount == 0)
        #expect(try await state.loadSyncState().photos.first?.destinationAlbumID == "album-frame-1")
    }

    @Test("Current photo destination state is not replaced by stale cleanup ownership")
    func photoDestinationIgnoresStaleManagedAlbum() async throws {
        let mappingID = UUID()
        let asset = photoAsset(id: "apple-photo")
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-stale",
                attributes: SkylightAlbumAttributes(
                    title: "Original Album",
                    messageCount: 0,
                    createdAt: nil,
                    updatedAt: nil
                )
            ),
            SkylightResource(
                id: "album-current",
                attributes: SkylightAlbumAttributes(
                    title: "Renamed Album",
                    messageCount: 0,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        ])
        var initial = SyncState()
        initial.photoAlbums = [PhotoAlbumRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            albumID: "album-stale"
        )]
        initial.photoDestinations = [PhotoDestinationSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            albumID: "album-current"
        )]
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(assets: [asset]),
            imageConverter: CoordinatorImageConverter(convertedAssetID: asset.id),
            state: state
        )
        var mapping = PhotoMapping(
            name: "Family",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Family",
            destinationAlbumTitle: "Original Album"
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        #expect(await api.addedToAlbumCalls.map { $0.albumID } == ["album-current"])
        #expect(
            try await state.loadSyncState().photoDestinations.first?.albumID
                == "album-current"
        )
    }

    @Test("An explicit new-album intent replaces an older recorded destination")
    func explicitNewPhotoDestinationIgnoresOldState() async throws {
        let mappingID = UUID()
        let oldIntentID = UUID()
        let newIntentID = UUID()
        let asset = photoAsset(id: "apple-photo")
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-old",
                attributes: SkylightAlbumAttributes(
                    title: "Replacement Album",
                    messageCount: 0,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        ])
        await api.configureAlbumCreationAllowed(true)
        var initial = SyncState()
        initial.photoDestinations = [PhotoDestinationSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            albumID: "album-old",
            destinationIntentID: oldIntentID
        )]
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(assets: [asset]),
            imageConverter: CoordinatorImageConverter(convertedAssetID: asset.id),
            state: state
        )
        var mapping = PhotoMapping(
            name: "Family",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Family",
            destinationAlbumTitle: "Replacement Album"
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]
        configuration.photoDestinationIntentIDsByFrame[
            FrameDestinationIdentity.key(mappingID: mappingID, frameID: "frame-1")
        ] = newIntentID

        _ = try await coordinator.sync(configuration: configuration)

        #expect(await api.createdAlbumTitles == ["Replacement Album"])
        #expect(await api.addedToAlbumCalls.map { $0.albumID } == ["created-album"])
        let destination = try #require(
            try await state.loadSyncState().photoDestinations.first
        )
        #expect(destination.albumID == "created-album")
        #expect(destination.destinationIntentID == newIntentID)
    }

    @Test("A failed first upload reuses the album created for its intent")
    func createdPhotoDestinationIsCheckpointedBeforeRendering() async throws {
        let mappingID = UUID()
        let intentID = UUID()
        let asset = photoAsset(id: "apple-photo")
        let api = CoordinatorAPIStub()
        await api.configureAlbumCreationAllowed(true)
        let state = CoordinatorStateStore()
        let converter = CoordinatorImageConverter(
            convertedAssetID: asset.id,
            failuresBeforeSuccess: 1
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(assets: [asset]),
            imageConverter: converter,
            state: state
        )
        var mapping = PhotoMapping(
            name: "Family",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Family",
            destinationAlbumTitle: "Family"
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]
        configuration.photoDestinationIntentIDsByFrame[
            FrameDestinationIdentity.key(mappingID: mappingID, frameID: "frame-1")
        ] = intentID

        do {
            _ = try await coordinator.sync(configuration: configuration)
            Issue.record("Expected the first conversion to fail")
        } catch CoordinatorStubError.unexpectedCall {
            // Expected after the destination checkpoint.
        }
        let checkpoint = try await state.loadSyncState()
        #expect(checkpoint.photoAlbums.map(\.albumID) == ["created-album"])
        #expect(checkpoint.photoDestinations.map(\.albumID) == ["created-album"])

        _ = try await coordinator.sync(configuration: configuration)

        #expect(await api.createdAlbumTitles == ["Family"])
    }

    @Test("A missing Reminders list skips only its mapping and warns")
    func missingReminderListSkipsOnlyThatMapping() async throws {
        let api = CoordinatorAPIStub()
        await api.configureLists([], items: [])
        let reminderSource = CoordinatorReminderSource(
            reminders: [],
            missingListIDs: ["deleted-list"]
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            reminderSource: reminderSource
        )
        let missing = ReminderListMapping(
            sourceListID: "deleted-list",
            sourceListTitle: "Personal",
            destinationListTitle: "Dad's To-dos",
            destinationKind: .toDo,
            direction: .twoWay,
            enabled: true
        )
        let healthy = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListTitle: "Grocery List",
            destinationKind: .shopping,
            direction: .twoWay,
            enabled: true
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.reminderMappings = [missing, healthy]

        let summary = try await coordinator.sync(configuration: configuration)

        #expect(summary.reminders.warnings.count == 1)
        #expect(summary.reminders.warnings.first?.contains("Personal \u{2192} Dad's To-dos") == true)
        #expect(summary.reminders.warnings.first?.contains("deleted-list was not found") == true)
        #expect(await api.snapshot().createdLists == 1)
    }

    @Test("A missing Photos collection skips only its mapping and warns")
    func missingPhotoCollectionSkipsOnlyThatMapping() async throws {
        let api = CoordinatorAPIStub()
        await api.configureLists([], items: [])
        let photoSource = CoordinatorPhotoSource(
            collections: ["album-ok": []],
            missingCollectionIDs: ["album-gone"]
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: photoSource
        )
        var gone = PhotoMapping()
        gone.name = "Vacation"
        gone.sourceCollectionID = "album-gone"
        var healthy = PhotoMapping()
        healthy.name = "Kids"
        healthy.sourceCollectionID = "album-ok"
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [gone, healthy]

        let summary = try await coordinator.sync(configuration: configuration)

        #expect(summary.photos.warnings.count == 1)
        #expect(summary.photos.warnings.first?.contains("Vacation") == true)
        #expect(summary.photos.warnings.first?.contains("album-gone was not found") == true)
    }

    @Test("Returning to a frame reuses its recorded reminder list after a rename")
    func reminderDestinationUsesFrameScopedState() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists([
            SkylightResource(
                id: "list-frame-1",
                attributes: SkylightListAttributes(
                    label: "Renamed on Skylight",
                    color: "#2178AF",
                    kind: .toDo,
                    hideOnDevice: false
                )
            )
        ], items: [])
        var initial = SyncState()
        initial.reminderLists = [ReminderListSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "list-frame-1",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Groceries"
        )]
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)
        var mapping = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListTitle: "Original List Name",
            destinationKind: .toDo,
            direction: .appleToSkylight,
            enabled: true
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.reminderMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        #expect(await api.snapshot().createdLists == 0)
        #expect(try await state.loadSyncState().reminderLists.first?.skylightListID == "list-frame-1")
    }

    @Test("An explicit new-list intent replaces an older recorded destination")
    func explicitNewReminderDestinationIgnoresOldState() async throws {
        let mappingID = UUID()
        let oldIntentID = UUID()
        let newIntentID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists([
            SkylightResource(
                id: "list-old",
                attributes: SkylightListAttributes(
                    label: "Replacement List",
                    color: "#2178AF",
                    kind: .toDo,
                    hideOnDevice: false
                )
            )
        ], items: [])
        var initial = SyncState()
        initial.reminderLists = [ReminderListSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "list-old",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Old List",
            destinationIntentID: oldIntentID
        )]
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)
        var mapping = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListTitle: "Replacement List",
            destinationKind: .toDo,
            direction: .appleToSkylight,
            enabled: true
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.reminderMappings = [mapping]
        configuration.reminderDestinationIntentIDsByFrame[
            FrameDestinationIdentity.key(mappingID: mappingID, frameID: "frame-1")
        ] = newIntentID

        _ = try await coordinator.sync(configuration: configuration)

        #expect(await api.snapshot().createdLists == 1)
        let destination = try #require(
            try await state.loadSyncState().reminderLists.first
        )
        #expect(destination.skylightListID == "remote-list")
        #expect(destination.destinationIntentID == newIntentID)
    }

    @Test("An unchanged photo is not rendered again, and older state gains a fingerprint")
    func unchangedPhotoIsNotReRendered() async throws {
        let mappingID = UUID()
        let asset = photoAsset(id: "apple-photo")
        var mapping = PhotoMapping(
            name: "Our House",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Our House",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Our House"
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        func run(storedFingerprint: String?) async throws -> (renders: Int, persisted: SyncState) {
            let api = CoordinatorAPIStub()
            await api.configureAlbums([
                SkylightResource(
                    id: "album-1",
                    attributes: SkylightAlbumAttributes(
                        title: "Our House",
                        messageCount: 1,
                        createdAt: nil,
                        updatedAt: nil
                    )
                )
            ])
            var stateValue = SyncState()
            stateValue.photos = [PhotoSyncRecord(
                mappingID: mappingID,
                frameID: "frame-1",
                destinationAlbumID: "album-1",
                appleAssetID: "apple-photo",
                renderedHash: "rendered-hash",
                skylightMessageID: "message-1",
                skylightAlbumIDs: ["album-1"],
                lastSyncedAt: Date(timeIntervalSince1970: 100),
                sourceFingerprint: storedFingerprint
            )]
            let state = CoordinatorStateStore(state: stateValue)
            let photoSource = CoordinatorPhotoSource(assets: [asset])
            let coordinator = makeCoordinator(
                api: api,
                reminders: [],
                photoSource: photoSource,
                imageConverter: CoordinatorImageConverter(convertedAssetID: "apple-photo"),
                state: state
            )
            _ = try await coordinator.sync(configuration: configuration)
            return (photoSource.renderCount, try await state.loadSyncState())
        }

        // State written before fingerprints existed renders once more, then
        // records the fingerprint so later runs can skip the work.
        let upgrade = try await run(storedFingerprint: nil)
        #expect(upgrade.renders == 1)
        let fingerprint = try #require(upgrade.persisted.photos.first?.sourceFingerprint)

        let steady = try await run(storedFingerprint: fingerprint)
        #expect(steady.renders == 0)
    }

    @Test("A photo whose Apple asset changed is rendered again")
    func editedPhotoIsReRendered() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Our House",
                    messageCount: 1,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        ])
        let edited = ApplePhotoAssetSnapshot(
            id: "apple-photo",
            mediaKind: .image,
            pixelWidth: 1,
            pixelHeight: 1,
            creationDate: nil,
            modificationDate: nil,
            adjustmentDate: Date(timeIntervalSince1970: 900),
            contentTypeIdentifier: "public.jpeg",
            isFavorite: false,
            isHidden: false,
            hasAdjustments: true
        )
        var stateValue = SyncState()
        stateValue.photos = [PhotoSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            destinationAlbumID: "album-1",
            appleAssetID: "apple-photo",
            renderedHash: "rendered-hash",
            skylightMessageID: "message-1",
            skylightAlbumIDs: ["album-1"],
            lastSyncedAt: Date(timeIntervalSince1970: 100),
            sourceFingerprint: "stale-fingerprint"
        )]
        let photoSource = CoordinatorPhotoSource(assets: [edited])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: photoSource,
            imageConverter: CoordinatorImageConverter(convertedAssetID: "apple-photo"),
            state: CoordinatorStateStore(state: stateValue)
        )
        var mapping = PhotoMapping(
            name: "Our House",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Our House",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Our House"
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        #expect(photoSource.renderCount == 1)
    }

    @Test("A failed old-photo cleanup remains durable and retries")
    func editedPhotoCleanupRetriesAfterFailure() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Our House", messageCount: 1, createdAt: nil, updatedAt: nil
                )
            ),
            SkylightResource(
                id: "album-2",
                attributes: SkylightAlbumAttributes(
                    title: "Favorites", messageCount: 1, createdAt: nil, updatedAt: nil
                )
            )
        ])
        await api.configureDeleteMessageFailure(
            SkylightAPIError.httpStatus(code: 503, endpoint: "messages", body: "")
        )
        let edited = photoAsset(id: "apple-photo")
        var stateValue = SyncState()
        stateValue.photos = [PhotoSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            destinationAlbumID: "album-1",
            appleAssetID: "apple-photo",
            renderedHash: "old-hash",
            skylightMessageID: "old-message",
            skylightAlbumIDs: ["album-1"],
            lastSyncedAt: Date(timeIntervalSince1970: 100),
            sourceFingerprint: "stale-fingerprint"
        )]
        let state = CoordinatorStateStore(state: stateValue)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(assets: [edited]),
            imageConverter: CoordinatorImageConverter(
                convertedAssetID: "apple-photo",
                sha256: "new-hash"
            ),
            state: state
        )
        var mapping = PhotoMapping(
            name: "Our House",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Our House",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Our House"
        )
        mapping.id = mappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        var firstError: (any Error)?
        do {
            _ = try await coordinator.sync(configuration: configuration)
        } catch {
            firstError = error
        }
        let interrupted = try await state.loadSyncState()

        #expect(firstError != nil)
        #expect(interrupted.photos.first?.skylightMessageID == "message-1")
        #expect(interrupted.pendingPhotoCleanups.map(\.skylightMessageID) == ["old-message"])

        await api.configureDeleteMessageFailure(nil)
        _ = try await coordinator.sync(configuration: configuration)
        let recovered = try await state.loadSyncState()

        #expect(recovered.pendingPhotoCleanups.isEmpty)
        #expect(await api.deletedMessageIDs == ["old-message"])
        #expect(await api.removedFromAlbumMessageIDs == ["old-message", "old-message"])
        #expect(await api.uploadCount == 1)
    }

    @Test("Moving one shared photo keeps albums owned by the other photo")
    func movingSharedPhotoPreservesOtherOwnerAlbum() async throws {
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Shared", messageCount: 1, createdAt: nil, updatedAt: nil
                )
            ),
            SkylightResource(
                id: "album-2",
                attributes: SkylightAlbumAttributes(
                    title: "Moved", messageCount: 0, createdAt: nil, updatedAt: nil
                )
            )
        ])
        let mappingAID = UUID()
        let mappingBID = UUID()
        var mappingA = PhotoMapping(
            name: "Moved",
            sourceCollectionID: "col-a",
            sourceCollectionTitle: "A",
            destinationAlbumID: "album-2",
            destinationAlbumTitle: "Moved"
        )
        mappingA.id = mappingAID
        var mappingB = PhotoMapping(
            name: "Shared",
            sourceCollectionID: "col-b",
            sourceCollectionTitle: "B",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Shared"
        )
        mappingB.id = mappingBID
        var recordA = photoRecord(
            mappingID: mappingAID, appleAssetID: "asset-a", messageID: "message-1"
        )
        recordA.renderedHash = "rendered-hash"
        var recordB = photoRecord(
            mappingID: mappingBID, appleAssetID: "asset-b", messageID: "message-1"
        )
        recordB.renderedHash = "rendered-hash"
        var stateValue = SyncState()
        stateValue.photos = [recordA, recordB]
        let state = CoordinatorStateStore(state: stateValue)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(collections: [
                "col-a": [photoAsset(id: "asset-a")],
                "col-b": [photoAsset(id: "asset-b")]
            ]),
            imageConverter: CoordinatorImageConverter(convertedAssetID: "asset-a"),
            state: state
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mappingA, mappingB]

        _ = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()
        let persistedRecordA = try #require(
            persisted.photos.first { $0.mappingID == mappingAID }
        )
        let persistedRecordB = try #require(
            persisted.photos.first { $0.mappingID == mappingBID }
        )

        #expect(await api.removedFromAlbumMessageIDs.isEmpty)
        #expect(persistedRecordA.skylightAlbumIDs == ["album-2"])
        #expect(persistedRecordB.skylightAlbumIDs == ["album-1"])
    }

    @Test("A selected photo name updates its linked Skylight caption")
    func selectedPhotoNameUpdatesSkylightCaption() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Our House",
                    messageCount: 1,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        ])
        var stateValue = SyncState()
        stateValue.photos = [PhotoSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            destinationAlbumID: "album-1",
            appleAssetID: "apple-photo",
            renderedHash: "rendered-hash",
            skylightMessageID: "message-1",
            skylightAlbumIDs: ["album-1"],
            lastSyncedAt: Date(timeIntervalSince1970: 100)
        )]
        let state = CoordinatorStateStore(state: stateValue)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(assets: [photoAsset(id: "apple-photo")]),
            imageConverter: CoordinatorImageConverter(convertedAssetID: "apple-photo"),
            state: state
        )
        var mapping = PhotoMapping(
            name: "Our House",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Our House",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Our House"
        )
        mapping.id = mappingID
        mapping.selectedPhotoNames = ["apple-photo": "Backyard birthday"]
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        let firstSummary = try await coordinator.sync(configuration: configuration)
        var persisted = try await state.loadSyncState()

        #expect(firstSummary.photos.applied == 1)
        #expect(await api.messageCaptionUpdates == ["Backyard birthday [sb:rendered-has]"])
        #expect(persisted.photos.first?.lastSyncedCaption == "Backyard birthday")

        configuration.photoMappings[0].selectedPhotoNames = [:]
        let secondSummary = try await coordinator.sync(configuration: configuration)
        persisted = try await state.loadSyncState()

        #expect(secondSummary.photos.applied == 1)
        #expect(await api.messageCaptionUpdates == [
            "Backyard birthday [sb:rendered-has]",
            "[sb:rendered-has]"
        ])
        #expect(persisted.photos.first?.lastSyncedCaption == nil)
    }

    @Test("Clearing one shared photo name preserves another owner's caption")
    func clearingSharedPhotoNamePreservesOtherOwnerCaption() async throws {
        let mappingAID = UUID()
        let mappingBID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Shared",
                    messageCount: 1,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        ])
        var recordA = photoRecord(
            mappingID: mappingAID,
            appleAssetID: "asset-a",
            messageID: "message-1"
        )
        recordA.renderedHash = "rendered-hash"
        recordA.lastSyncedCaption = "Birthday"
        var recordB = photoRecord(
            mappingID: mappingBID,
            appleAssetID: "asset-b",
            messageID: "message-1"
        )
        recordB.renderedHash = "rendered-hash"
        recordB.lastSyncedCaption = "Birthday"
        var stateValue = SyncState()
        stateValue.photos = [recordA, recordB]
        let state = CoordinatorStateStore(state: stateValue)
        let assets = [photoAsset(id: "asset-a"), photoAsset(id: "asset-b")]
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(collections: [
                "col-a": [assets[0]],
                "col-b": [assets[1]]
            ]),
            imageConverter: CoordinatorImageConverter(
                convertedAssetID: "converted",
                sha256: "rendered-hash"
            ),
            state: state
        )
        var mappingA = PhotoMapping(
            name: "Shared A",
            sourceCollectionID: "col-a",
            sourceCollectionTitle: "Shared A",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Shared"
        )
        mappingA.id = mappingAID
        var mappingB = PhotoMapping(
            name: "Shared B",
            sourceCollectionID: "col-b",
            sourceCollectionTitle: "Shared B",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Shared"
        )
        mappingB.id = mappingBID
        mappingB.selectedPhotoNames = ["asset-b": "Birthday"]
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mappingA, mappingB]

        _ = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(await api.messageCaptionUpdates == ["Birthday [sb:rendered-has]"])
        #expect(persisted.photos.first { $0.mappingID == mappingAID }?.lastSyncedCaption == nil)
        #expect(persisted.photos.first { $0.mappingID == mappingBID }?.lastSyncedCaption == "Birthday")
    }

    @Test("Removing the last named photo owner clears a shared caption")
    func removingLastNamedPhotoOwnerClearsSharedCaption() async throws {
        let mappingAID = UUID()
        let mappingBID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Shared",
                    messageCount: 1,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        ])
        var recordA = photoRecord(
            mappingID: mappingAID,
            appleAssetID: "asset-a",
            messageID: "message-1"
        )
        recordA.renderedHash = "rendered-hash"
        recordA.lastSyncedCaption = "Birthday"
        var recordB = photoRecord(
            mappingID: mappingBID,
            appleAssetID: "asset-b",
            messageID: "message-1"
        )
        recordB.renderedHash = "rendered-hash"
        recordB.lastSyncedCaption = "Birthday"
        var stateValue = SyncState()
        stateValue.photos = [recordA, recordB]
        let state = CoordinatorStateStore(state: stateValue)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(collections: [
                "col-a": [photoAsset(id: "asset-a")],
                "col-b": []
            ]),
            imageConverter: CoordinatorImageConverter(
                convertedAssetID: "converted",
                sha256: "rendered-hash"
            ),
            state: state
        )
        var mappingA = PhotoMapping(
            name: "Shared A",
            sourceCollectionID: "col-a",
            sourceCollectionTitle: "Shared A",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Shared"
        )
        mappingA.id = mappingAID
        var mappingB = PhotoMapping(
            name: "Shared B",
            sourceCollectionID: "col-b",
            sourceCollectionTitle: "Shared B",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Shared"
        )
        mappingB.id = mappingBID
        mappingB.selectedPhotoNames = ["asset-b": "Birthday"]
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mappingA, mappingB]

        _ = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(await api.messageCaptionUpdates == [
            "Birthday [sb:rendered-has]",
            "[sb:rendered-has]"
        ])
        #expect(persisted.photos.count == 1)
        #expect(persisted.photos.first?.mappingID == mappingAID)
        #expect(persisted.photos.first?.lastSyncedCaption == nil)
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

    @Test("A deselected reminder stays dormant during Skylight-to-Apple sync")
    func deselectedReminderDoesNotRecreateOnApple() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists(
            [remoteReminderList()],
            items: [remoteReminderItem(id: "remote-item", title: "Milk")]
        )
        var initial = SyncState()
        initial.reminders = [
            reminderRecordFor(mappingID: mappingID, appleID: "apple-item", itemID: "remote-item")
        ]
        let state = CoordinatorStateStore(state: initial)
        let reminderSource = CoordinatorReminderSource(
            reminders: [reminder(id: "apple-item", title: "Milk")],
            allowsCreation: true
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].id = mappingID
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = .skylightToApple
        configuration.reminderMappings[0].selectionMode = .selectedItems
        configuration.reminderMappings[0].selectedReminderIDs = []

        _ = try await coordinator.sync(configuration: configuration)
        _ = try await coordinator.sync(configuration: configuration)

        #expect(reminderSource.createdReminders.isEmpty)
        #expect(try await state.loadSyncState().reminders.count == 1)
    }

    @Test("A selected reminder recreated from Skylight keeps its selection anchor")
    func recreatedSelectedReminderDoesNotRepeat() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists(
            [remoteReminderList()],
            items: [remoteReminderItem(id: "remote-item", title: "Milk")]
        )
        var initial = SyncState()
        initial.reminders = [
            reminderRecordFor(mappingID: mappingID, appleID: "apple-deleted", itemID: "remote-item")
        ]
        let state = CoordinatorStateStore(state: initial)
        let reminderSource = CoordinatorReminderSource(
            reminders: [],
            allowsCreation: true,
            allowsUpdate: true
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].id = mappingID
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = .skylightToApple
        configuration.reminderMappings[0].selectionMode = .selectedItems
        configuration.reminderMappings[0].selectedReminderIDs = ["apple-deleted"]

        _ = try await coordinator.sync(configuration: configuration)
        await api.configureLists(
            [remoteReminderList()],
            items: [remoteReminderItem(id: "remote-item", title: "Whole milk")]
        )
        _ = try await coordinator.sync(configuration: configuration)
        _ = try await coordinator.sync(configuration: configuration)

        let records = try await state.loadSyncState().reminders
        #expect(reminderSource.createdReminders.count == 1)
        #expect(reminderSource.updatedReminders.count == 1)
        #expect(records.count == 1)
        #expect(records.first?.appleReminderID == "created-reminder-1")
        #expect(records.first?.selectionSourceReminderID == "apple-deleted")
    }

    @Test("Syncing into an existing Skylight list adopts matching items instead of duplicating them")
    func adoptionLinksMatchingReminderItems() async throws {
        let api = CoordinatorAPIStub()
        await api.configureLists(
            [SkylightResource(
                id: "remote-list",
                attributes: SkylightListAttributes(
                    label: "Groceries",
                    color: nil,
                    kind: .shopping,
                    hideOnDevice: nil
                )
            )],
            items: [SkylightResource(
                id: "remote-milk",
                attributes: SkylightListItemAttributes(
                    label: "Milk",
                    status: .pending,
                    section: nil,
                    position: nil
                )
            )]
        )
        let state = CoordinatorStateStore()
        let reminders = [
            reminder(id: "apple-bread", title: "Bread"),
            reminder(id: "apple-milk", title: "Milk")
        ]
        let coordinator = makeCoordinator(api: api, reminders: reminders, state: state)
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = .twoWay

        let summary = try await coordinator.sync(configuration: configuration)
        let calls = await api.snapshot()
        let persisted = try await state.loadSyncState()

        #expect(summary.reminders.planned == 1)
        #expect(calls.createdItems == 1)
        #expect(persisted.reminders.count == 2)
        let adopted = persisted.reminders.first { $0.appleReminderID == "apple-milk" }
        #expect(adopted?.skylightItemID == "remote-milk")
    }

    @Test("A renamed Apple list updates its linked Skylight list")
    func reminderListMetadataUpdatesSkylight() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists([
            SkylightResource(
                id: "remote-list",
                attributes: SkylightListAttributes(
                    label: "Groceries",
                    color: nil,
                    kind: .shopping,
                    hideOnDevice: false
                )
            )
        ], items: [])
        var stateValue = SyncState()
        stateValue.reminderLists = [ReminderListSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "remote-list",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Groceries"
        )]
        let state = CoordinatorStateStore(state: stateValue)
        let reminderSource = CoordinatorReminderSource(
            reminders: [],
            listTitle: "Weekend groceries"
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].id = mappingID
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = .twoWay

        let summary = try await coordinator.sync(configuration: configuration)
        let requests = await api.listUpdateRequests
        let persisted = try await state.loadSyncState()

        #expect(summary.reminders.applied == 1)
        #expect(requests.map(\.label) == ["Weekend groceries"])
        #expect(persisted.reminderLists.first?.lastSyncedAppleTitle == "Weekend groceries")
        #expect(persisted.reminderLists.first?.lastSyncedSkylightTitle == "Weekend groceries")
    }

    @Test("A renamed Skylight list updates its linked Apple list")
    func reminderListMetadataUpdatesApple() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists([
            SkylightResource(
                id: "remote-list",
                attributes: SkylightListAttributes(
                    label: "Family essentials",
                    color: nil,
                    kind: .shopping,
                    hideOnDevice: false
                )
            )
        ], items: [])
        var stateValue = SyncState()
        stateValue.reminderLists = [ReminderListSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "remote-list",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Groceries"
        )]
        let state = CoordinatorStateStore(state: stateValue)
        let reminderSource = CoordinatorReminderSource(reminders: [])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].id = mappingID
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = .twoWay

        let summary = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(summary.reminders.applied == 1)
        #expect(reminderSource.listTitle == "Family essentials")
        #expect(persisted.reminderLists.first?.lastSyncedAppleTitle == "Family essentials")
        #expect(persisted.reminderLists.first?.lastSyncedSkylightTitle == "Family essentials")
    }

    @Test("A changed Apple list color updates its linked Skylight list")
    func reminderListColorUpdatesSkylight() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists([
            SkylightResource(
                id: "remote-list",
                attributes: SkylightListAttributes(
                    label: "Groceries",
                    color: nil,
                    kind: .shopping,
                    hideOnDevice: false
                )
            )
        ], items: [])
        var stateValue = SyncState()
        stateValue.reminderLists = [ReminderListSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "remote-list",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Groceries",
            lastSyncedAppleColor: "#2178AF",
            lastSyncedSkylightColor: nil
        )]
        let state = CoordinatorStateStore(state: stateValue)
        let reminderSource = CoordinatorReminderSource(
            reminders: [],
            listColorHex: "#FD7A33"
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].id = mappingID
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = .twoWay

        let summary = try await coordinator.sync(configuration: configuration)
        let requests = await api.listUpdateRequests
        let persisted = try await state.loadSyncState()

        #expect(summary.reminders.applied == 1)
        #expect(requests.last?.label == nil)
        #expect(requests.last?.color == "#FD7A33")
        #expect(persisted.reminderLists.first?.lastSyncedSkylightColor == "#FD7A33")
    }

    @Test("A changed Skylight list color updates its linked Apple list")
    func reminderListColorUpdatesApple() async throws {
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists([
            SkylightResource(
                id: "remote-list",
                attributes: SkylightListAttributes(
                    label: "Groceries",
                    color: "#34C759",
                    kind: .shopping,
                    hideOnDevice: false
                )
            )
        ], items: [])
        var stateValue = SyncState()
        stateValue.reminderLists = [ReminderListSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "remote-list",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Groceries",
            lastSyncedAppleColor: nil,
            lastSyncedSkylightColor: "#2178AF"
        )]
        let state = CoordinatorStateStore(state: stateValue)
        let reminderSource = CoordinatorReminderSource(
            reminders: [],
            listColorHex: nil
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )
        var configuration = configuredReminders(dryRun: false)
        configuration.reminderMappings[0].id = mappingID
        configuration.reminderMappings[0].destinationListID = "remote-list"
        configuration.reminderMappings[0].direction = .twoWay

        let summary = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(summary.reminders.applied == 1)
        #expect(reminderSource.listColorHex == "#34C759")
        #expect(persisted.reminderLists.first?.lastSyncedAppleColor == "#34C759")
    }

    @Test("Two-way recipes pull a new Skylight recipe into the notes folder")
    func recipePullCreatesNote() async throws {
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            remoteRecipe(
                id: "recipe-1",
                title: "Tacos",
                description: "Family favorite",
                ingredients: ["Shells"],
                updatedAt: "rev-1"
            )
        ])
        let notesSource = CoordinatorNotesSource()
        let state = CoordinatorStateStore()
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource
        )

        let summary = try await coordinator.sync(configuration: configuredRecipes())
        let created = await notesSource.createdBodies
        let persisted = try await state.loadSyncState()

        #expect(summary.recipes.planned == 1)
        #expect(summary.recipes.applied == 1)
        #expect(created.count == 1)
        #expect(created[0].contains("<h1>Tacos</h1>"))
        #expect(persisted.notes.count == 1)
        #expect(persisted.notes[0].skylightID == "recipe-1")
        #expect(persisted.notes[0].lastSkylightUpdatedAt == "rev-1")
    }

    @Test("A note with attachments is never rewritten by a Skylight edit")
    func recipeAttachmentNoteIsNotRewritten() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        var initial = SyncState()
        initial.notes = [recipeSyncRecord(
            noteID: "note-1",
            contentHash: sha(plaintext),
            skylightID: "recipe-1",
            remoteRevision: "rev-1"
        )]
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            remoteRecipe(
                id: "recipe-1",
                title: "Tacos",
                description: "Remote edit",
                updatedAt: "rev-2"
            )
        ])
        await api.configureMealCategories(mealCategories)
        let notesSource = CoordinatorNotesSource(
            notes: [note],
            attachmentCounts: ["note-1": 2]
        )
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource
        )

        let summary = try await coordinator.sync(configuration: configuredRecipes())
        let updated = await notesSource.updatedBodiesByNoteID
        let persisted = try await state.loadSyncState()

        #expect(summary.recipes.planned == 0)
        #expect(updated.isEmpty)
        #expect(persisted.notes[0].lastSkylightUpdatedAt == "rev-2")
    }

    @Test("A Skylight recipe edit rewrites the unchanged linked note")
    func recipeRemoteEditRewritesNote() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        var initial = SyncState()
        initial.notes = [recipeSyncRecord(
            noteID: "note-1",
            contentHash: sha(plaintext),
            skylightID: "recipe-1",
            remoteRevision: "rev-1"
        )]
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            remoteRecipe(
                id: "recipe-1",
                title: "Tacos",
                description: "Ingredients\n- Shells\n- Cheese\n\nInstructions\n1. Fill",
                ingredients: ["Shells", "Cheese"],
                updatedAt: "rev-2"
            )
        ])
        await api.configureMealCategories(mealCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource
        )

        let summary = try await coordinator.sync(configuration: configuredRecipes())
        let updated = await notesSource.updatedBodiesByNoteID
        let calls = await api.snapshot()
        let persisted = try await state.loadSyncState()

        #expect(summary.recipes.applied == 1)
        #expect(updated["note-1"]?.contains("Cheese") == true)
        #expect(calls.updatedRecipes == 0)
        #expect(persisted.notes[0].lastSkylightUpdatedAt == "rev-2")
    }

    @Test("Conflicting recipe edits follow the Apple-wins policy")
    func recipeConflictAppleWins() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        var initial = SyncState()
        initial.notes = [recipeSyncRecord(
            noteID: "note-1",
            contentHash: "stale-apple-hash",
            skylightID: "recipe-1",
            remoteRevision: "rev-1"
        )]
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            remoteRecipe(
                id: "recipe-1",
                title: "Tacos",
                description: "Remote edit",
                updatedAt: "rev-2"
            )
        ])
        await api.configureMealCategories(mealCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource
        )
        var configuration = configuredRecipes()
        configuration.recipeSelection.conflictPolicy = .appleWins

        let summary = try await coordinator.sync(configuration: configuration)
        let updatedNotes = await notesSource.updatedBodiesByNoteID
        let calls = await api.snapshot()
        let updatedIDs = await api.updatedRecipeIDs
        let persisted = try await state.loadSyncState()

        #expect(summary.recipes.applied == 1)
        #expect(calls.updatedRecipes == 1)
        #expect(updatedIDs == ["recipe-1"])
        #expect(updatedNotes.isEmpty)
        #expect(persisted.notes[0].contentHash == sha(plaintext))
        #expect(persisted.notes[0].lastSkylightUpdatedAt == "rev-update-1")
    }

    @Test("Conflicting recipe edits follow the Skylight-wins policy")
    func recipeConflictSkylightWins() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        var initial = SyncState()
        initial.notes = [recipeSyncRecord(
            noteID: "note-1",
            contentHash: "stale-apple-hash",
            skylightID: "recipe-1",
            remoteRevision: "rev-1"
        )]
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            remoteRecipe(
                id: "recipe-1",
                title: "Tacos",
                description: "Remote edit",
                updatedAt: "rev-2"
            )
        ])
        await api.configureMealCategories(mealCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource
        )
        var configuration = configuredRecipes()
        configuration.recipeSelection.conflictPolicy = .skylightWins

        let summary = try await coordinator.sync(configuration: configuration)
        let updatedNotes = await notesSource.updatedBodiesByNoteID
        let calls = await api.snapshot()

        #expect(summary.recipes.applied == 1)
        #expect(calls.updatedRecipes == 0)
        #expect(updatedNotes["note-1"]?.contains("Remote edit") == true)
    }

    @Test("A recipe deleted on Skylight trashes its linked note")
    func recipeRemoteDeletionTrashesNote() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        var initial = SyncState()
        initial.notes = [recipeSyncRecord(
            noteID: "note-1",
            contentHash: sha(plaintext),
            skylightID: "recipe-1",
            remoteRevision: "rev-1"
        )]
        let api = CoordinatorAPIStub()
        await api.configureMealCategories(mealCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource
        )

        let summary = try await coordinator.sync(configuration: configuredRecipes())
        let trashed = await notesSource.trashedNoteIDs
        let calls = await api.snapshot()
        let persisted = try await state.loadSyncState()

        #expect(summary.recipes.applied == 1)
        #expect(trashed == ["note-1"])
        #expect(calls.deletedRecipes == 0)
        #expect(persisted.notes.isEmpty)
    }

    @Test("Linking a folder adopts an identical Skylight recipe without changes")
    func recipeAdoptionLinksIdenticalContent() async throws {
        let draft = RecipeDraft(
            title: "Tacos",
            description: "Family favorite",
            servings: "6",
            ingredients: ["Shells", "Cheese"],
            instructions: ["Fill the shells."],
            tags: ["dinner"],
            sourceURL: "https://example.com/tacos"
        )
        let note = recipeNote(id: "note-1", plaintext: RecipeNoteFormatter.plaintext(for: draft))
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            SkylightResource(
                id: "recipe-1",
                attributes: SkylightRecipeAttributes(
                    summary: draft.title,
                    description: RecipeNoteFormatter.skylightDescription(for: draft),
                    ingredients: draft.ingredients,
                    url: draft.sourceURL,
                    imageURL: nil,
                    createdAt: nil,
                    updatedAt: "rev-1"
                )
            )
        ])
        await api.configureMealCategories(mealCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore()
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource
        )

        let summary = try await coordinator.sync(configuration: configuredRecipes())
        let calls = await api.snapshot()
        let created = await notesSource.createdBodies
        let updated = await notesSource.updatedBodiesByNoteID
        let persisted = try await state.loadSyncState()

        #expect(summary.recipes.planned == 0)
        #expect(calls.createdRecipes == 0)
        #expect(calls.updatedRecipes == 0)
        #expect(created.isEmpty)
        #expect(updated.isEmpty)
        #expect(persisted.notes.count == 1)
        #expect(persisted.notes[0].skylightID == "recipe-1")
    }

    @Test("Deleting a photo mapping purges its photos and its now-empty bridge album")
    func purgePhotoMappingRemovesManagedPhotos() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.photos = [
            photoRecord(mappingID: mappingID, appleAssetID: "a1", messageID: "m1"),
            photoRecord(mappingID: mappingID, appleAssetID: "a2", messageID: "m2")
        ]
        initial.photoAlbums = [
            PhotoAlbumRecord(mappingID: mappingID, frameID: "frame-1", albumID: "album-1")
        ]
        let api = CoordinatorAPIStub()
        await api.configureAlbumMessages(["album-1": []])
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        let purge = try await coordinator.purgePhotoMapping(mappingID: mappingID, frameID: "frame-1")
        let deleted = await api.deletedMessageIDs
        let removedFromAlbums = await api.removedFromAlbumMessageIDs
        let deletedAlbums = await api.deletedAlbumIDs
        let persisted = try await state.loadSyncState()

        #expect(purge.photos == 2)
        #expect(purge.albums == 1)
        #expect(Set(deleted) == ["m1", "m2"])
        #expect(Set(removedFromAlbums) == ["m1", "m2"])
        #expect(deletedAlbums == ["album-1"])
        #expect(persisted.photos.isEmpty)
        #expect(persisted.photoAlbums.isEmpty)
    }

    @Test("A transient failure during photo purge keeps the records for a retry")
    func transientPurgeFailureKeepsRecords() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.photos = [
            photoRecord(mappingID: mappingID, appleAssetID: "a1", messageID: "m1"),
            photoRecord(mappingID: mappingID, appleAssetID: "a2", messageID: "m2")
        ]
        let api = CoordinatorAPIStub()
        await api.configureDeleteMessageFailure(
            SkylightAPIError.httpStatus(code: 503, endpoint: "messages", body: "")
        )
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        var caught: (any Error)?
        do {
            _ = try await coordinator.purgePhotoMapping(mappingID: mappingID, frameID: "frame-1")
        } catch {
            caught = error
        }
        let persisted = try await state.loadSyncState()

        #expect(caught != nil)
        #expect(persisted.photos.count == 2)
    }

    @Test("A Skylight copy that is already gone counts as purged")
    func alreadyAbsentMessageCountsAsPurged() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.photos = [
            photoRecord(mappingID: mappingID, appleAssetID: "a1", messageID: "m1")
        ]
        let api = CoordinatorAPIStub()
        await api.configureDeleteMessageFailure(
            SkylightAPIError.httpStatus(code: 404, endpoint: "messages", body: "")
        )
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        let purge = try await coordinator.purgePhotoMapping(mappingID: mappingID, frameID: "frame-1")
        let persisted = try await state.loadSyncState()

        #expect(purge.photos == 1)
        #expect(persisted.photos.isEmpty)
    }

    @Test("A bridge album that still holds photos is kept when the mapping is deleted")
    func purgePhotoMappingKeepsNonEmptyAlbum() async throws {        let mappingID = UUID()
        var initial = SyncState()
        initial.photos = [photoRecord(mappingID: mappingID, appleAssetID: "a1", messageID: "m1")]
        initial.photoAlbums = [
            PhotoAlbumRecord(mappingID: mappingID, frameID: "frame-1", albumID: "album-1")
        ]
        let api = CoordinatorAPIStub()
        // The user added a photo to this album on Skylight, so it is not empty.
        await api.configureAlbumMessages(["album-1": ["user-added-message"]])
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        let purge = try await coordinator.purgePhotoMapping(mappingID: mappingID, frameID: "frame-1")
        let deletedAlbums = await api.deletedAlbumIDs
        let persisted = try await state.loadSyncState()

        #expect(purge.photos == 1)
        #expect(purge.albums == 0)
        #expect(deletedAlbums.isEmpty)
        #expect(persisted.photoAlbums.isEmpty)
    }

    @Test("Photo purge spans every frame recorded for the mapping")
    func purgePhotoMappingAcrossFrames() async throws {
        let mappingID = UUID()
        var first = photoRecord(mappingID: mappingID, appleAssetID: "a1", messageID: "m1")
        var second = photoRecord(mappingID: mappingID, appleAssetID: "a1", messageID: "m2")
        first.frameID = "frame-1"
        second.frameID = "frame-2"
        var initial = SyncState()
        initial.photos = [first, second]
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        let purge = try await coordinator.purgePhotoMapping(
            mappingID: mappingID,
            frameID: "frame-2"
        )

        #expect(purge.photos == 2)
        #expect(Set(await api.deletedMessageIDs) == ["m1", "m2"])
        #expect(await api.deletedMessageRequests
            .map { "\($0.frameID):\($0.messageID)" }
            .sorted() == ["frame-1:m1", "frame-2:m2"])
        #expect(try await state.loadSyncState().photos.isEmpty)
    }

    @Test("Purging one deduplicated photo owner preserves the shared message")
    func purgePhotoMappingPreservesSharedMessage() async throws {
        let removedMappingID = UUID()
        let retainedMappingID = UUID()
        var initial = SyncState()
        initial.photos = [
            photoRecord(mappingID: removedMappingID, appleAssetID: "a1", messageID: "shared"),
            photoRecord(mappingID: retainedMappingID, appleAssetID: "a2", messageID: "shared")
        ]
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        let purge = try await coordinator.purgePhotoMapping(
            mappingID: removedMappingID,
            frameID: "frame-1"
        )
        let persisted = try await state.loadSyncState()

        #expect(purge.photos == 1)
        #expect(await api.deletedMessageIDs.isEmpty)
        #expect(await api.removedFromAlbumMessageIDs.isEmpty)
        #expect(persisted.photos.map(\.mappingID) == [retainedMappingID])
    }

    @Test("Album inventory failure keeps its managed record for a retry")
    func purgePhotoMappingPropagatesAlbumInventoryFailure() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.photoAlbums = [
            PhotoAlbumRecord(mappingID: mappingID, frameID: "frame-1", albumID: "album-1")
        ]
        let api = CoordinatorAPIStub()
        await api.configureAlbumMessageListFailure(CoordinatorStubError.unexpectedCall)
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        do {
            _ = try await coordinator.purgePhotoMapping(
                mappingID: mappingID,
                frameID: "frame-1"
            )
            Issue.record("Expected album inventory to fail")
        } catch CoordinatorStubError.unexpectedCall {
            // Expected. The mapping owner can retry the purge.
        }

        #expect(try await state.loadSyncState().photoAlbums == initial.photoAlbums)
    }

    @Test("An already deleted managed album completes a retried purge")
    func alreadyAbsentAlbumCompletesPurge() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.photoAlbums = [
            PhotoAlbumRecord(mappingID: mappingID, frameID: "frame-1", albumID: "album-1")
        ]
        let api = CoordinatorAPIStub()
        await api.configureAlbumMessageListFailure(
            SkylightAPIError.httpStatus(code: 404, endpoint: "albums", body: "")
        )
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        let purge = try await coordinator.purgePhotoMapping(
            mappingID: mappingID,
            frameID: "frame-1"
        )

        #expect(purge.albums == 1)
        #expect(await api.deletedAlbumIDs.isEmpty)
        #expect(try await state.loadSyncState().photoAlbums.isEmpty)
    }

    @Test("Deleting a reminder mapping can clear the Skylight side")
    func purgeReminderMappingSkylightSide() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.reminders = [
            reminderRecordFor(mappingID: mappingID, appleID: "a1", itemID: "s1"),
            reminderRecordFor(mappingID: mappingID, appleID: "a2", itemID: "s2")
        ]
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore(state: initial)
        let reminderSource = CoordinatorReminderSource(reminders: [])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )

        let affected = try await coordinator.purgeReminderMapping(
            mappingID: mappingID,
            frameID: "frame-1",
            side: .skylight
        )
        let deletedItems = await api.deletedListItemIDs
        let persisted = try await state.loadSyncState()

        #expect(affected == 2)
        #expect(Set(deletedItems) == ["s1", "s2"])
        #expect(reminderSource.removedReminderIDs.isEmpty)
        #expect(persisted.reminders.isEmpty)
    }

    @Test("Deleting a reminder mapping can clear the Apple side")
    func purgeReminderMappingAppleSide() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.reminders = [reminderRecordFor(mappingID: mappingID, appleID: "a1", itemID: "s1")]
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore(state: initial)
        let reminderSource = CoordinatorReminderSource(reminders: [])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )

        let affected = try await coordinator.purgeReminderMapping(
            mappingID: mappingID,
            frameID: "frame-1",
            side: .appleReminders
        )
        let deletedItems = await api.deletedListItemIDs
        let persisted = try await state.loadSyncState()

        #expect(affected == 1)
        #expect(reminderSource.removedReminderIDs == ["a1"])
        #expect(deletedItems.isEmpty)
        #expect(persisted.reminders.isEmpty)
    }

    @Test("An already deleted Apple reminder completes a retried purge")
    func alreadyAbsentAppleReminderCompletesPurge() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.reminders = [
            reminderRecordFor(mappingID: mappingID, appleID: "a1", itemID: "s1")
        ]
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore(state: initial)
        let reminderSource = CoordinatorReminderSource(
            reminders: [],
            removalError: AppleRemindersStoreError.reminderNotFound("a1")
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )

        let affected = try await coordinator.purgeReminderMapping(
            mappingID: mappingID,
            frameID: "frame-1",
            side: .appleReminders
        )

        #expect(affected == 1)
        #expect(reminderSource.removedReminderIDs.isEmpty)
        #expect(try await state.loadSyncState().reminders.isEmpty)
    }

    @Test("Removing a mapping with no cleanup only forgets its records")
    func purgeReminderMappingNoneClearsRecords() async throws {
        let mappingID = UUID()
        var initial = SyncState()
        initial.reminders = [reminderRecordFor(mappingID: mappingID, appleID: "a1", itemID: "s1")]
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore(state: initial)
        let reminderSource = CoordinatorReminderSource(reminders: [])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            reminderSource: reminderSource
        )

        let affected = try await coordinator.purgeReminderMapping(
            mappingID: mappingID,
            frameID: "frame-1",
            side: .none
        )
        let deletedItems = await api.deletedListItemIDs
        let persisted = try await state.loadSyncState()

        #expect(affected == 0)
        #expect(reminderSource.removedReminderIDs.isEmpty)
        #expect(deletedItems.isEmpty)
        #expect(persisted.reminders.isEmpty)
    }

    @Test("Reminder purge routes each stored link to its own frame")
    func purgeReminderMappingAcrossFrames() async throws {
        let mappingID = UUID()
        var first = reminderRecordFor(mappingID: mappingID, appleID: "a1", itemID: "s1")
        var second = reminderRecordFor(mappingID: mappingID, appleID: "a1", itemID: "s2")
        first.frameID = "frame-1"
        first.skylightListID = "list-1"
        second.frameID = "frame-2"
        second.skylightListID = "list-2"
        var initial = SyncState()
        initial.reminders = [first, second]
        let api = CoordinatorAPIStub()
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(api: api, reminders: [], state: state)

        let affected = try await coordinator.purgeReminderMapping(
            mappingID: mappingID,
            frameID: "frame-2",
            side: .skylight
        )

        #expect(affected == 2)
        #expect(await api.deletedListItemRequests
            .map { "\($0.frameID):\($0.listID):\($0.itemID)" }
            .sorted() == ["frame-1:list-1:s1", "frame-2:list-2:s2"])
        #expect(try await state.loadSyncState().reminders.isEmpty)
    }

    @Test("Chore sync stays two-way and creates a linked repeating Apple reminder")
    func syncsRecurringChoreToAppleFromLegacyOneWayMapping() async throws {
        let api = CoordinatorAPIStub()
        await api.configureChores([
            SkylightResource(
                id: "chore-1",
                attributes: SkylightChoreAttributes(
                    summary: "Water plants",
                    description: "Kitchen herbs",
                    group: nil,
                    status: .pending,
                    start: "2026-07-15",
                    startTime: nil,
                    completedOn: nil,
                    rewardPoints: nil,
                    recurring: true,
                    recurringUntil: nil,
                    recurrenceSet: ["FREQ=DAILY;INTERVAL=1"],
                    upForGrabs: false,
                    emojiIcon: nil,
                    routine: true,
                    position: nil
                ),
                relationships: [
                    "categories": SkylightRelationship(
                        data: .many([SkylightIdentifier(id: "person-1", type: "category")])
                    )
                ]
            )
        ])
        let choreSource = CoordinatorChoreReminderSource()
        let state = CoordinatorStateStore()
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            choreReminderSource: choreSource
        )
        var mapping = ChoreMapping()
        mapping.frameID = "frame-1"
        mapping.frameName = "Kitchen"
        mapping.direction = .appleToSkylight
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1",
            memberLabel: "Oliver",
            appleListID: "list-1",
            appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        let summary = try await coordinator.sync(configuration: configuration)
        let created = choreSource.createdReminders
        let persisted = try await state.loadSyncState()

        #expect(summary.chores.applied == 1)
        #expect(created.count == 1)
        #expect(created.first?.title == "Water plants")
        #expect(created.first?.recurrence?.frequency == .daily)
        #expect(persisted.chores.count == 1)
        #expect(persisted.chores.first?.skylightSeriesID == "chore-1")
    }

    @Test("Completed chores stay complete after creation or adoption", arguments: [false, true])
    func completedChoresRemainComplete(adoptExisting: Bool) async throws {
        let api = CoordinatorAPIStub()
        await api.configureChores([
            SkylightResource(
                id: "chore-1",
                attributes: SkylightChoreAttributes(
                    summary: "Water plants",
                    description: "Kitchen herbs",
                    group: nil,
                    status: .complete,
                    start: "2026-07-15",
                    startTime: nil,
                    completedOn: nil,
                    rewardPoints: nil,
                    recurring: true,
                    recurringUntil: nil,
                    recurrenceSet: ["FREQ=DAILY;INTERVAL=1"],
                    upForGrabs: false,
                    emojiIcon: nil,
                    routine: true,
                    position: nil
                ),
                relationships: [
                    "categories": SkylightRelationship(
                        data: .many([SkylightIdentifier(id: "person-1", type: "category")])
                    )
                ]
            )
        ])
        let choreSource = CoordinatorChoreReminderSource(reminders: adoptExisting ? [
            ChoreReminderSnapshot(
                id: "existing-apple", listID: "list-1", memberKey: "person-1",
                title: "Water plants", notes: "Kitchen herbs", isCompleted: false,
                dueDate: Date(timeIntervalSince1970: 1_784_131_200),
                recurrence: ParsedRecurrenceRule(frequency: .daily), recurrenceUnsupported: false,
                modifiedAt: Date(timeIntervalSince1970: 1_784_131_200)
            )
        ] : [])
        let state = CoordinatorStateStore()
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            choreReminderSource: choreSource,
            now: { Date(timeIntervalSince1970: 1_784_131_200) }
        )
        var mapping = ChoreMapping()
        mapping.frameID = "frame-1"
        mapping.frameName = "Kitchen"
        mapping.direction = .appleToSkylight
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1",
            memberLabel: "Oliver",
            appleListID: "list-1",
            appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)
        _ = try await coordinator.sync(configuration: configuration)
        _ = try await coordinator.sync(configuration: configuration)
        #expect(choreSource.createdReminders.count == (adoptExisting ? 0 : 1))
        #expect(await api.choreCompletionRequests.isEmpty)
        let stored = try await state.loadSyncState()
        #expect(stored.chores.count == 1)
        #expect(stored.chores.first?.baselineCompletedInstanceDate == "2026-07-15")
    }

    @Test("A repeating Apple chore creates a recurring Skylight routine")
    func syncsRecurringAppleChoreToSkylightFromLegacyOneWayMapping() async throws {
        let today = Date(timeIntervalSince1970: 1_784_073_600)
        let api = CoordinatorAPIStub()
        let choreSource = CoordinatorChoreReminderSource(reminders: [
            ChoreReminderSnapshot(
                id: "apple-chore-1",
                listID: "list-1",
                memberKey: "person-1",
                title: "Water plants",
                notes: "Kitchen herbs",
                isCompleted: false,
                dueDate: today,
                recurrence: ParsedRecurrenceRule(frequency: .daily),
                recurrenceUnsupported: false,
                modifiedAt: today
            )
        ])
        let state = CoordinatorStateStore()
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            choreReminderSource: choreSource,
            now: { today }
        )
        var mapping = ChoreMapping()
        mapping.frameID = "frame-1"
        mapping.frameName = "Kitchen"
        mapping.direction = .skylightToApple
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1",
            memberLabel: "Oliver",
            appleListID: "list-1",
            appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        let summary = try await coordinator.sync(configuration: configuration)
        let requests = await api.choreRequests
        let persisted = try await state.loadSyncState()

        #expect(summary.chores.applied == 1)
        #expect(requests.count == 1)
        #expect(requests.first?.summary == "Water plants")
        #expect(requests.first?.recurring == true)
        #expect(requests.first?.routine == true)
        #expect(requests.first?.recurrenceSet?.first?.hasPrefix("RRULE:FREQ=DAILY") == true)
        #expect(persisted.chores.count == 1)
        #expect(persisted.chores.first?.appleReminderID == "apple-chore-1")
    }

    @Test("Chore query bounds use the selected frame timezone")
    func choreQueryUsesFrameTimezone() async throws {
        let instant = try #require(
            ISO8601DateFormatter().date(from: "2026-08-28T05:00:00Z")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let api = CoordinatorAPIStub()
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            choreReminderSource: CoordinatorChoreReminderSource(),
            calendar: calendar,
            now: { instant }
        )
        var mapping = ChoreMapping()
        mapping.frameID = "frame-1"
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1",
            memberLabel: "Oliver",
            appleListID: "list-1",
            appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        #expect(await api.choreListRequests.first?.after == "2026-08-27")
        #expect(await api.choreListRequests.first?.before == "2026-08-29")
    }

    @Test("Chore due dates preserve the frame wall clock across Mac timezones")
    func choreDueDatesUseFrameCalendar() throws {
        var macCalendar = Calendar(identifier: .gregorian)
        macCalendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        var frameCalendar = Calendar(identifier: .gregorian)
        frameCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        var dateOnly = DateComponents()
        dateOnly.calendar = macCalendar
        dateOnly.timeZone = macCalendar.timeZone
        dateOnly.year = 2026
        dateOnly.month = 8
        dateOnly.day = 28
        let dateOnlyValue = try #require(
            AppleRemindersStore.choreDate(from: dateOnly, calendar: frameCalendar)
        )
        let dateOnlyRoundTrip = AppleRemindersStore.choreDateComponents(
            dateOnlyValue,
            calendar: frameCalendar
        )

        #expect(dateOnlyRoundTrip.year == 2026)
        #expect(dateOnlyRoundTrip.month == 8)
        #expect(dateOnlyRoundTrip.day == 28)
        #expect(dateOnlyRoundTrip.hour == nil)
        #expect(dateOnlyRoundTrip.minute == nil)

        var timed = dateOnly
        timed.hour = 14
        timed.minute = 30
        let timedValue = try #require(
            AppleRemindersStore.choreDate(from: timed, calendar: frameCalendar)
        )
        let timedRoundTrip = AppleRemindersStore.choreDateComponents(
            timedValue,
            calendar: frameCalendar
        )

        #expect(timedRoundTrip.year == 2026)
        #expect(timedRoundTrip.month == 8)
        #expect(timedRoundTrip.day == 28)
        #expect(timedRoundTrip.hour == 14)
        #expect(timedRoundTrip.minute == 30)
    }

    @Test("Meal weekdays resolve from the selected frame timezone")
    func mealDateUsesFrameTimezone() throws {
        let instant = try #require(
            ISO8601DateFormatter().date(from: "2026-08-28T05:00:00Z")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let resolver = DefaultMealDateResolver(calendar: calendar)

        let resolved = try resolver.resolveMealDate("Thursday", relativeTo: instant)

        #expect(resolved == "2026-09-03")
    }

    @Test("A rolled occurrence stays complete through repeated sync and content edits", arguments: [false, true])
    func rebindsRolledRecurringReminderIdentifier(editOnApple: Bool) async throws {
        let today = Date(timeIntervalSince1970: 1_784_131_200)
        let nextDay = Date(timeIntervalSince1970: 1_784_217_600)
        let api = CoordinatorAPIStub()
        await api.configureChores([
            SkylightResource(
                id: "chore-1",
                attributes: SkylightChoreAttributes(
                    summary: "Water plants",
                    description: nil,
                    group: nil,
                    status: .pending,
                    start: "2026-07-15",
                    startTime: nil,
                    completedOn: nil,
                    rewardPoints: nil,
                    recurring: true,
                    recurringUntil: nil,
                    recurrenceSet: ["FREQ=DAILY;INTERVAL=1"],
                    upForGrabs: false,
                    emojiIcon: nil,
                    routine: true,
                    position: nil
                ),
                relationships: [
                    "category": SkylightRelationship(
                        data: .many([SkylightIdentifier(id: "person-1", type: "category")])
                    )
                ]
            )
        ])
        let mappingID = UUID()
        let rolledReminder = ChoreReminderSnapshot(
            id: "apple-new-occurrence",
            listID: "list-1",
            memberKey: "person-1",
            title: "Water plants",
            notes: nil,
            isCompleted: false,
            dueDate: nextDay,
            recurrence: ParsedRecurrenceRule(frequency: .daily),
            recurrenceUnsupported: false,
            modifiedAt: today
        )
        let choreSource = CoordinatorChoreReminderSource(reminders: [rolledReminder])
        var initialState = SyncState()
        initialState.chores = [ChoreSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleReminderID: "apple-old-occurrence",
            skylightSeriesID: "chore-1",
            memberKey: "person-1",
            lastAppleModifiedAt: today,
            lastSkylightModifiedAt: today,
            contentFingerprint: "",
            lastSyncedTitle: "Water plants",
            lastSyncedRecurrence: "FREQ=DAILY;INTERVAL=1",
            baselineDueDate: today
        )]
        let state = CoordinatorStateStore(state: initialState)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            choreReminderSource: choreSource,
            now: { today }
        )
        var mapping = ChoreMapping()
        mapping.id = mappingID
        mapping.frameID = "frame-1"
        mapping.frameName = "Kitchen"
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1",
            memberLabel: "Oliver",
            appleListID: "list-1",
            appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        let summary = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(summary.chores.applied == 1)
        #expect(await api.completedChoreSeriesIDs == ["chore-1"])
        #expect(persisted.chores.first?.appleReminderID == "apple-new-occurrence")
        #expect(persisted.chores.first?.baselineCompletedInstanceDate == "2026-07-15")
        #expect(persisted.chores.first?.baselineDueDate == nextDay)
        let reloadedState = try JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(persisted))
        try await state.saveSyncState(reloadedState)
        _ = try await coordinator.sync(configuration: configuration)
        _ = try await coordinator.sync(configuration: configuration)
        #expect(await api.choreCompletionRequests.map(\.status) == [.complete])
        await api.configureChoreUpdatesAllowed(true)
        if editOnApple {
            _ = try choreSource.syncUpdateChoreReminder(withID: "apple-new-occurrence", patch: ChoreReminderPatch(
                title: "Updated plants", notes: nil, dueDate: nextDay,
                recurrence: rolledReminder.recurrence, replaceRecurrence: false
            ), memberKey: "person-1")
        } else {
            _ = try await api.updateChore(frameID: "frame-1", choreID: "chore-1",
                                         request: SkylightChoreRequest(summary: "Updated plants"))
        }
        _ = try await coordinator.sync(configuration: configuration)
        _ = try await coordinator.sync(configuration: configuration)
        #expect(await api.choreCompletionRequests.map(\.status) == [.complete])
        #expect(await api.choreRequests.allSatisfy { $0.status != .pending })
        let finalApple = try await choreSource.syncChoreReminders(in: "list-1", memberKey: "person-1")
        #expect(finalApple.first?.dueDate == nextDay)
        #expect(finalApple.first?.title == "Updated plants")
    }

    @Test("An unsupported recurring reminder rebinds to a new occurrence without duplicating")
    func rebindsUnsupportedRecurringReminder() async throws {
        let today = Date(timeIntervalSince1970: 1_784_131_200)
        let nextDay = Date(timeIntervalSince1970: 1_784_217_600)
        let api = CoordinatorAPIStub()
        await api.configureChoreUpdatesAllowed(true)
        await api.configureChores([
            SkylightResource(
                id: "chore-1",
                attributes: SkylightChoreAttributes(
                    summary: "Water plants",
                    description: nil,
                    group: nil,
                    status: .pending,
                    start: "2026-07-16",
                    startTime: nil,
                    completedOn: nil,
                    rewardPoints: nil,
                    recurring: true,
                    recurringUntil: nil,
                    recurrenceSet: ["FREQ=DAILY;INTERVAL=1"],
                    upForGrabs: false,
                    emojiIcon: nil,
                    routine: true,
                    position: nil
                ),
                relationships: [
                    "category": SkylightRelationship(
                        data: .many([SkylightIdentifier(id: "person-1", type: "category")])
                    )
                ]
            )
        ])
        let mappingID = UUID()
        let staleCompleted = ChoreReminderSnapshot(
            id: "apple-old-completed",
            listID: "list-1",
            memberKey: "person-1",
            title: "Water plants",
            notes: nil,
            isCompleted: true,
            dueDate: today,
            recurrence: nil,
            recurrenceUnsupported: true,
            modifiedAt: today
        )
        let newOccurrence = ChoreReminderSnapshot(
            id: "apple-new-occurrence",
            listID: "list-1",
            memberKey: "person-1",
            title: "Water plants",
            notes: nil,
            isCompleted: false,
            dueDate: nextDay,
            recurrence: nil,
            recurrenceUnsupported: true,
            modifiedAt: nextDay
        )
        let choreSource = CoordinatorChoreReminderSource(
            reminders: [staleCompleted, newOccurrence]
        )
        var initialState = SyncState()
        initialState.chores = [ChoreSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleReminderID: "apple-old-completed",
            skylightSeriesID: "chore-1",
            memberKey: "person-1",
            lastAppleModifiedAt: today,
            lastSkylightModifiedAt: today,
            contentFingerprint: "",
            lastSyncedTitle: "Water plants",
            lastSyncedRecurrence: "FREQ=DAILY;INTERVAL=1",
            baselineDueDate: today,
            baselineCompletedInstanceDate: "2026-07-15"
        )]
        let state = CoordinatorStateStore(state: initialState)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            choreReminderSource: choreSource,
            now: { nextDay }
        )
        var mapping = ChoreMapping()
        mapping.id = mappingID
        mapping.frameID = "frame-1"
        mapping.frameName = "Kitchen"
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1",
            memberLabel: "Oliver",
            appleListID: "list-1",
            appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        let summary = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(persisted.chores.count == 1)
        #expect(persisted.chores.first?.appleReminderID == "apple-new-occurrence")
        #expect(choreSource.createdReminders.isEmpty)
        #expect(summary.chores.applied == 2)
    }

    @Test("A stale completed recurring reminder collapses multiple replacement occurrences")
    func collapsesDuplicateRecurringReminderOccurrences() async throws {
        let today = Date(timeIntervalSince1970: 1_784_131_200)
        let nextDay = Date(timeIntervalSince1970: 1_784_217_600)
        let api = CoordinatorAPIStub()
        await api.configureChores([
            SkylightResource(
                id: "chore-1",
                attributes: SkylightChoreAttributes(
                    summary: "Water plants", status: .pending,
                    start: "2026-07-16", recurring: true,
                    recurrenceSet: ["FREQ=DAILY;INTERVAL=1"],
                    upForGrabs: false, routine: true
                ),
                relationships: [
                    "category": SkylightRelationship(
                        data: .many([SkylightIdentifier(id: "person-1", type: "category")])
                    )
                ]
            )
        ])
        let mappingID = UUID()
        func reminder(_ id: String, completed: Bool, modifiedAt: Date) -> ChoreReminderSnapshot {
            ChoreReminderSnapshot(
                id: id, listID: "list-1", memberKey: "person-1",
                title: "Water plants", notes: nil, isCompleted: completed,
                dueDate: completed ? today : nextDay,
                recurrence: ParsedRecurrenceRule(frequency: .daily),
                recurrenceUnsupported: false, modifiedAt: modifiedAt
            )
        }
        let choreSource = CoordinatorChoreReminderSource(reminders: [
            reminder("apple-old-completed", completed: true, modifiedAt: today),
            reminder("apple-duplicate-a", completed: false, modifiedAt: today),
            reminder("apple-current", completed: false, modifiedAt: nextDay),
            reminder("apple-duplicate-b", completed: false, modifiedAt: today)
        ])
        var initialState = SyncState()
        initialState.chores = [ChoreSyncRecord(
            mappingID: mappingID, frameID: "frame-1",
            appleReminderID: "apple-old-completed", skylightSeriesID: "chore-1",
            memberKey: "person-1", lastAppleModifiedAt: today,
            lastSkylightModifiedAt: today, contentFingerprint: "",
            lastSyncedTitle: "Water plants",
            lastSyncedRecurrence: "FREQ=DAILY;INTERVAL=1",
            baselineDueDate: today, baselineCompletedInstanceDate: "2026-07-15"
        )]
        let state = CoordinatorStateStore(state: initialState)
        let coordinator = makeCoordinator(
            api: api, reminders: [], state: state,
            choreReminderSource: choreSource, now: { nextDay }
        )
        var mapping = ChoreMapping()
        mapping.id = mappingID
        mapping.frameID = "frame-1"
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1", memberLabel: "Oliver",
            appleListID: "list-1", appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        let summary = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(persisted.chores.count == 1)
        #expect(persisted.chores.first?.appleReminderID == "apple-current")
        #expect(choreSource.removedReminderIDs == ["apple-duplicate-a", "apple-duplicate-b"])
        #expect(choreSource.createdReminders.isEmpty)
        #expect(await api.choreRequests.isEmpty)
        #expect(summary.chores.applied == 3)
    }

    @Test("A Skylight-deleted recurring reminder is not resurrected on the next sync")
    func skylightDeletedRecurringReminderStaysDeleted() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists(
            [SkylightResource(
                id: "remote-list",
                attributes: SkylightListAttributes(
                    label: "Family",
                    color: nil,
                    kind: .toDo,
                    hideOnDevice: nil
                )
            )],
            items: []
        )
        var initialState = SyncState()
        initialState.reminders = [
            reminderRecordFor(mappingID: mappingID, appleID: "apple-recur", itemID: "remote-item-1")
        ]
        let state = CoordinatorStateStore(state: initialState)

        // The recurring item was deleted on Skylight; the Apple reminder and
        // its record survive with a suppression marker.
        _ = try await coordinatorSyncingRecurringReminders(
            api: api, state: state, mappingID: mappingID,
            reminders: [recurringReminder(id: "apple-recur", title: "Item")],
            now: fixedNow
        )
        // The next run plans nothing: no re-creation, no deletion.
        _ = try await coordinatorSyncingRecurringReminders(
            api: api, state: state, mappingID: mappingID,
            reminders: [recurringReminder(id: "apple-recur", title: "Item")],
            now: fixedNow
        )

        let calls = await api.snapshot()
        let persisted = try await state.loadSyncState()

        #expect(calls.createdItems == 0)
        #expect(await api.deletedListItemIDs.isEmpty)
        #expect(persisted.reminders.count == 1)
        #expect(persisted.reminders.first?.appleReminderID == "apple-recur")
        #expect(persisted.reminders.first?.remoteSuppressedAt != nil)
    }

    @Test("Editing the spared Apple reminder after a Skylight deletion re-creates it")
    func editedRecurringReminderRecreatesAfterSkylightDeletion() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let mappingID = UUID()
        let api = CoordinatorAPIStub()
        await api.configureLists(
            [SkylightResource(
                id: "remote-list",
                attributes: SkylightListAttributes(
                    label: "Family",
                    color: nil,
                    kind: .toDo,
                    hideOnDevice: nil
                )
            )],
            items: []
        )
        var initialState = SyncState()
        initialState.reminders = [
            reminderRecordFor(mappingID: mappingID, appleID: "apple-recur", itemID: "remote-item-1")
        ]
        let state = CoordinatorStateStore(state: initialState)

        _ = try await coordinatorSyncingRecurringReminders(
            api: api, state: state, mappingID: mappingID,
            reminders: [recurringReminder(id: "apple-recur", title: "Item")],
            now: fixedNow
        )

        // An edit on Apple after the suppression lifts it and pushes a fresh
        // copy to Skylight.
        _ = try await coordinatorSyncingRecurringReminders(
            api: api, state: state, mappingID: mappingID,
            reminders: [
                recurringReminder(
                    id: "apple-recur",
                    title: "Item",
                    modifiedAt: fixedNow.addingTimeInterval(60)
                )
            ],
            now: fixedNow
        )

        let calls = await api.snapshot()
        let persisted = try await state.loadSyncState()

        #expect(calls.createdItems == 1)
        #expect(persisted.reminders.count == 1)
        #expect(persisted.reminders.first?.skylightItemID == "remote-item-1")
        #expect(persisted.reminders.first?.remoteSuppressedAt == nil)
    }

    private func coordinatorSyncingRecurringReminders(
        api: CoordinatorAPIStub,
        state: CoordinatorStateStore,
        mappingID: UUID,
        reminders: [AppleReminderSnapshot],
        now: Date
    ) async throws -> SyncRunSummary {
        var mapping = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListTitle: "Family",
            destinationKind: .toDo,
            direction: .twoWay,
            enabled: true
        )
        mapping.id = mappingID
        mapping.destinationListID = "remote-list"
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.reminderMappings = [mapping]
        let coordinator = makeCoordinator(
            api: api, reminders: reminders, state: state, now: { now }
        )
        return try await coordinator.sync(configuration: configuration)
    }

    @Test("Occurrence collapse spares a same-title reminder with a different due date")
    func collapseSparesUnrelatedSameTitleReminder() async throws {
        let today = Date(timeIntervalSince1970: 1_784_131_200)
        let nextDay = Date(timeIntervalSince1970: 1_784_217_600)
        let api = CoordinatorAPIStub()
        await api.configureChores([
            SkylightResource(
                id: "chore-1",
                attributes: SkylightChoreAttributes(
                    summary: "Water plants", status: .pending,
                    start: "2026-07-16", recurring: true,
                    recurrenceSet: ["FREQ=DAILY;INTERVAL=1"],
                    upForGrabs: false, routine: true
                ),
                relationships: [
                    "category": SkylightRelationship(
                        data: .many([SkylightIdentifier(id: "person-1", type: "category")])
                    )
                ]
            )
        ])
        let mappingID = UUID()

        func reminder(_ id: String, completed: Bool, due: Date) -> ChoreReminderSnapshot {
            ChoreReminderSnapshot(
                id: id, listID: "list-1", memberKey: "person-1",
                title: "Water plants", notes: nil, isCompleted: completed,
                dueDate: due,
                recurrence: ParsedRecurrenceRule(frequency: .daily),
                recurrenceUnsupported: false, modifiedAt: today
            )
        }

        // The stale completed occurrence rolled forward into two fresh
        // occurrences of the same series (same due date) plus an unrelated
        // second reminder with the same title but its own schedule.
        let choreSource = CoordinatorChoreReminderSource(reminders: [
            reminder("apple-old-completed", completed: true, due: today),
            reminder("apple-duplicate-a", completed: false, due: nextDay),
            reminder("apple-current", completed: false, due: nextDay),
            reminder("apple-duplicate-b", completed: false, due: nextDay),
            reminder("apple-other-series", completed: false, due: today.addingTimeInterval(3_600))
        ])
        var initialState = SyncState()
        initialState.chores = [ChoreSyncRecord(
            mappingID: mappingID, frameID: "frame-1",
            appleReminderID: "apple-old-completed", skylightSeriesID: "chore-1",
            memberKey: "person-1", lastAppleModifiedAt: today,
            lastSkylightModifiedAt: today, contentFingerprint: "",
            lastSyncedTitle: "Water plants",
            lastSyncedRecurrence: "FREQ=DAILY;INTERVAL=1",
            baselineDueDate: today, baselineCompletedInstanceDate: "2026-07-15"
        )]
        let state = CoordinatorStateStore(state: initialState)
        let coordinator = makeCoordinator(
            api: api, reminders: [], state: state,
            choreReminderSource: choreSource, now: { nextDay }
        )
        var mapping = ChoreMapping()
        mapping.id = mappingID
        mapping.frameID = "frame-1"
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1", memberLabel: "Oliver",
            appleListID: "list-1", appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)
        let persisted = try await state.loadSyncState()

        #expect(choreSource.removedReminderIDs == ["apple-duplicate-a", "apple-duplicate-b"])
        #expect(persisted.chores.contains { $0.appleReminderID == "apple-other-series" })
    }

    @Test("A shared dedup message survives one of its owners being removed")
    func sharedMessageSurvivesSingleOwnerRemoval() async throws {
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Our House", messageCount: 1, createdAt: nil, updatedAt: nil
                )
            )
        ])
        await api.configureAlbumMessagesWithCaptions([
            "album-1": [(id: "message-1", caption: "[sb:rendered-has]")]
        ])
        let mappingAID = UUID()
        let mappingBID = UUID()

        var mappingA = PhotoMapping(
            name: "Favorites",
            sourceCollectionID: "col-a",
            sourceCollectionTitle: "col-a",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Our House"
        )
        mappingA.id = mappingAID
        var mappingB = PhotoMapping(
            name: "Our House",
            sourceCollectionID: "col-b",
            sourceCollectionTitle: "col-b",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Our House"
        )
        mappingB.id = mappingBID

        var stateValue = SyncState()
        var recordA = photoRecord(
            mappingID: mappingAID, appleAssetID: "asset-a", messageID: "message-1"
        )
        recordA.renderedHash = "rendered-hash"
        recordA.destinationAlbumID = "album-2"
        recordA.skylightAlbumIDs = ["album-2"]
        var recordB = photoRecord(
            mappingID: mappingBID, appleAssetID: "asset-b", messageID: "message-1"
        )
        recordB.renderedHash = "rendered-hash"
        stateValue.photos = [recordA, recordB]
        let state = CoordinatorStateStore(state: stateValue)

        // Mapping A's source is now empty, so its record enters the removal
        // pass; mapping B still syncs the same shared message.
        let photoSource = CoordinatorPhotoSource(collections: [
            "col-a": [],
            "col-b": [photoAsset(id: "asset-b")]
        ])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: photoSource,
            imageConverter: CoordinatorImageConverter(convertedAssetID: "asset-b"),
            state: state
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mappingA, mappingB]

        _ = try await coordinator.sync(configuration: configuration)

        let persisted = try await state.loadSyncState()

        #expect(await api.deletedMessageIDs.isEmpty)
        #expect(await api.removedFromAlbumMessageIDs == ["message-1"])
        #expect(await api.removedMessageRequests.first?.albumIDs == ["album-2"])
        #expect(persisted.photos.count == 1)
        #expect(persisted.photos.first?.appleAssetID == "asset-b")
    }

    @Test("Two byte-identical assets in one run upload once")
    func identicalAssetsUploadOncePerRun() async throws {
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Our House", messageCount: 0, createdAt: nil, updatedAt: nil
                )
            )
        ])
        let photoSource = CoordinatorPhotoSource(collections: [
            "apple-album": [photoAsset(id: "a-1"), photoAsset(id: "a-2")]
        ])
        let stateStore = CoordinatorStateStore()
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: photoSource,
            imageConverter: CoordinatorImageConverter(
                convertedAssetID: "a-1",
                sha256: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
            ),
            state: stateStore
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [
            PhotoMapping(
                name: "Our House",
                sourceCollectionID: "apple-album",
                sourceCollectionTitle: "Our House",
                destinationAlbumID: "album-1",
                destinationAlbumTitle: "Our House"
            )
        ]

        _ = try await coordinator.sync(configuration: configuration)

        let persisted = try await stateStore.loadSyncState()

        #expect(await api.uploadCount == 1)
        #expect(persisted.photos.count == 2)
        #expect(Set(persisted.photos.map(\.skylightMessageID)) == ["message-1"])
    }

    @Test("A moved message participates in deduplication later in the same run")
    func movedMessageRefreshesAlbumDedupCache() async throws {
        let mappingID = UUID()
        let hashA = "111111111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let hashB = "222222222222bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Destination", messageCount: 0, createdAt: nil, updatedAt: nil
                )
            ),
            SkylightResource(
                id: "album-2",
                attributes: SkylightAlbumAttributes(
                    title: "Old", messageCount: 1, createdAt: nil, updatedAt: nil
                )
            )
        ])
        await api.configureAlbumMessagesWithCaptions([
            "album-1": [],
            "album-2": [(id: "message-b", caption: PhotoDeduplication.tag(forRenderedHash: hashB))]
        ])
        var mapping = PhotoMapping(
            name: "Destination",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Destination",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Destination"
        )
        mapping.id = mappingID
        var initial = SyncState()
        initial.photos = [PhotoSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            destinationAlbumID: "album-2",
            appleAssetID: "asset-b",
            renderedHash: hashB,
            skylightMessageID: "message-b",
            skylightAlbumIDs: ["album-2"],
            lastSyncedAt: Date(timeIntervalSince1970: 100)
        )]
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: CoordinatorPhotoSource(collections: [
                "apple-album": [
                    photoAsset(id: "asset-a"),
                    photoAsset(id: "asset-b"),
                    photoAsset(id: "asset-c")
                ]
            ]),
            imageConverter: CoordinatorImageConverter(
                convertedAssetID: "converted",
                sha256ByAssetID: [
                    "asset-a": hashA,
                    "asset-b": hashB,
                    "asset-c": hashB
                ]
            ),
            state: state
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        let persisted = try await state.loadSyncState()
        #expect(await api.uploadCount == 1)
        #expect(persisted.photos.first { $0.appleAssetID == "asset-c" }?.skylightMessageID == "message-b")
    }

    @Test("A run over unchanged photos renders nothing and writes state a bounded number of times")
    func unchangedPhotosCoalesceCheckpoints() async throws {
        let mappingID = UUID()
        let assets = (1...30).map { photoAsset(id: "asset-\($0)") }
        var mapping = PhotoMapping(
            name: "Our House",
            sourceCollectionID: "apple-album",
            sourceCollectionTitle: "Our House",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Our House"
        )
        mapping.id = mappingID

        var initialState = SyncState()
        initialState.photos = assets.map { asset -> PhotoSyncRecord in
            var record = photoRecord(
                mappingID: mappingID, appleAssetID: asset.id, messageID: "msg-\(asset.id)"
            )
            record.sourceFingerprint = PhotoDeduplication.sourceFingerprint(
                for: asset,
                maximumLongEdge: mapping.maximumLongEdge,
                jpegQuality: mapping.jpegQuality
            )
            return record
        }
        let api = CoordinatorAPIStub()
        await api.configureAlbums([
            SkylightResource(
                id: "album-1",
                attributes: SkylightAlbumAttributes(
                    title: "Our House", messageCount: 30, createdAt: nil, updatedAt: nil
                )
            )
        ])
        let state = CoordinatorStateStore(state: initialState)
        let photoSource = CoordinatorPhotoSource(collections: ["apple-album": assets])
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            photoSource: photoSource,
            imageConverter: CoordinatorImageConverter(convertedAssetID: nil),
            state: state
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.photoMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        let persisted = try await state.loadSyncState()

        // Every asset matches its fingerprint, so the run neither renders
        // nor writes per photo; only domain-end bookkeeping saves remain.
        #expect(photoSource.renderCount == 0)
        #expect(await state.saveCount < assets.count)
        #expect(persisted.photos.count == assets.count)
    }

    @Test("Completing a one-off chore omits instance fields Skylight rejects (HTTP 422)")
    func completesNonRecurringChoreWithoutInstanceFields() async throws {
        let today = Date(timeIntervalSince1970: 1_784_131_200)
        let api = CoordinatorAPIStub()
        await api.configureChores([
            SkylightResource(
                id: "chore-1",
                attributes: SkylightChoreAttributes(
                    summary: "Water plants",
                    status: .pending,
                    start: "2026-07-15",
                    recurring: false,
                    recurrenceSet: nil,
                    upForGrabs: false,
                    routine: false
                ),
                relationships: [
                    "category": SkylightRelationship(
                        data: .many([SkylightIdentifier(id: "person-1", type: "category")])
                    )
                ]
            )
        ])
        let mappingID = UUID()
        let completedReminder = ChoreReminderSnapshot(
            id: "apple-chore-1",
            listID: "list-1",
            memberKey: "person-1",
            title: "Water plants",
            notes: nil,
            isCompleted: true,
            dueDate: today,
            recurrence: nil,
            recurrenceUnsupported: false,
            modifiedAt: today
        )
        let choreSource = CoordinatorChoreReminderSource(reminders: [completedReminder])
        var initialState = SyncState()
        initialState.chores = [ChoreSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleReminderID: "apple-chore-1",
            skylightSeriesID: "chore-1",
            memberKey: "person-1",
            lastAppleModifiedAt: today,
            lastSkylightModifiedAt: today,
            contentFingerprint: "",
            lastSyncedTitle: "Water plants",
            lastSyncedRecurrence: nil,
            baselineDueDate: today
        )]
        let state = CoordinatorStateStore(state: initialState)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            choreReminderSource: choreSource,
            now: { today }
        )
        var mapping = ChoreMapping()
        mapping.id = mappingID
        mapping.frameID = "frame-1"
        mapping.memberLinks = [ChoreMemberLink(
            memberKey: "person-1",
            memberLabel: "Oliver",
            appleListID: "list-1",
            appleListTitle: "Oliver Chores"
        )]
        var configuration = AppConfiguration()
        configuration.account.frameID = "frame-1"
        configuration.dryRun = false
        configuration.choreMappings = [mapping]

        _ = try await coordinator.sync(configuration: configuration)

        let completions = await api.choreCompletionRequests
        #expect(completions.count == 1)
        #expect(completions.first?.status == .complete)
        #expect(completions.first?.instanceDate == nil)
        #expect(completions.first?.instanceTime == nil)
    }

    @Test("Teardown keeping Skylight deletes the Apple reminders and their empty lists")
    func teardownKeepSkylightClearsAppleSide() async throws {
        let mappingID = UUID()
        let choreSource = CoordinatorChoreReminderSource(reminders: [
            choreReminderSnapshot(id: "apple-1", listID: "list-1", title: "Water plants"),
            choreReminderSnapshot(id: "apple-2", listID: "list-1", title: "Pack lunches")
        ])
        let api = CoordinatorAPIStub()
        var initialState = SyncState()
        initialState.chores = [
            teardownRecord(mappingID: mappingID, appleID: "apple-1", seriesID: "chore-1"),
            teardownRecord(mappingID: mappingID, appleID: "apple-2", seriesID: "chore-2")
        ]
        let state = CoordinatorStateStore(state: initialState)
        let coordinator = makeCoordinator(
            api: api, reminders: [], state: state, choreReminderSource: choreSource
        )

        let result = try await coordinator.teardownChoreMapping(
            mappingID: mappingID,
            frameID: "frame-1",
            mode: .keepSkylight,
            appleListIDs: ["list-1"]
        )

        #expect(result.skylightItemsRemoved == 0)
        #expect(result.appleItemsRemoved == 2)
        #expect(result.listsRemoved == 1)
        #expect(await api.deletedChoreRequests.isEmpty)
        #expect(choreSource.deletedListIDs == ["list-1"])
        #expect(try await state.loadSyncState().chores.isEmpty)
    }

    @Test("Chore teardown propagates an empty-list deletion failure")
    func teardownPropagatesListDeletionFailure() async throws {
        let mappingID = UUID()
        let choreSource = CoordinatorChoreReminderSource(
            reminders: [
                choreReminderSnapshot(id: "apple-1", listID: "list-1", title: "Water plants")
            ],
            listDeletionError: CoordinatorStubError.unexpectedCall
        )
        var initial = SyncState()
        initial.chores = [
            teardownRecord(mappingID: mappingID, appleID: "apple-1", seriesID: "chore-1")
        ]
        let state = CoordinatorStateStore(state: initial)
        let coordinator = makeCoordinator(
            api: CoordinatorAPIStub(), reminders: [], state: state,
            choreReminderSource: choreSource
        )

        do {
            _ = try await coordinator.teardownChoreMapping(
                mappingID: mappingID,
                frameID: "frame-1",
                mode: .keepSkylight,
                appleListIDs: ["list-1"]
            )
            Issue.record("Expected list deletion to fail")
        } catch CoordinatorStubError.unexpectedCall {
            // Expected. AppStore keeps the mapping, so the list deletion retries.
        }
    }

    @Test("Teardown keeping Reminders deletes only the Skylight chores")
    func teardownKeepRemindersClearsSkylightSide() async throws {
        let mappingID = UUID()
        let choreSource = CoordinatorChoreReminderSource(reminders: [
            choreReminderSnapshot(id: "apple-1", listID: "list-1", title: "Water plants")
        ])
        let api = CoordinatorAPIStub()
        var initialState = SyncState()
        initialState.chores = [
            teardownRecord(
                mappingID: mappingID, appleID: "apple-1", seriesID: "chore-1",
                recurrence: "FREQ=DAILY;INTERVAL=1"
            )
        ]
        let state = CoordinatorStateStore(state: initialState)
        let coordinator = makeCoordinator(
            api: api, reminders: [], state: state, choreReminderSource: choreSource
        )

        let result = try await coordinator.teardownChoreMapping(
            mappingID: mappingID,
            frameID: "frame-1",
            mode: .keepReminders,
            appleListIDs: ["list-1"]
        )

        #expect(result.skylightItemsRemoved == 1)
        #expect(result.appleItemsRemoved == 0)
        #expect(result.listsRemoved == 0)
        let deletions = await api.deletedChoreRequests
        #expect(deletions.map(\.choreID) == ["chore-1"])
        #expect(deletions.first?.applyToAll == true)
        #expect(choreSource.deletedListIDs.isEmpty)
        #expect(choreSource.removedReminderIDs.isEmpty)
        #expect(try await state.loadSyncState().chores.isEmpty)
    }

    private func choreReminderSnapshot(
        id: String,
        listID: String,
        title: String
    ) -> ChoreReminderSnapshot {
        ChoreReminderSnapshot(
            id: id,
            listID: listID,
            memberKey: "person-1",
            title: title,
            notes: nil,
            isCompleted: false,
            dueDate: nil,
            recurrence: nil,
            recurrenceUnsupported: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func teardownRecord(
        mappingID: UUID,
        appleID: String,
        seriesID: String,
        recurrence: String? = nil
    ) -> ChoreSyncRecord {
        ChoreSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleReminderID: appleID,
            skylightSeriesID: seriesID,
            memberKey: "person-1",
            lastAppleModifiedAt: Date(timeIntervalSince1970: 100),
            lastSkylightModifiedAt: Date(timeIntervalSince1970: 100),
            contentFingerprint: "",
            lastSyncedTitle: "Chore",
            lastSyncedRecurrence: recurrence
        )
    }

    private func makeCoordinator(
        api: CoordinatorAPIStub,
        reminders: [AppleReminderSnapshot],
        photoSource: CoordinatorPhotoSource = CoordinatorPhotoSource(),
        imageConverter: CoordinatorImageConverter = CoordinatorImageConverter(),
        state: CoordinatorStateStore = CoordinatorStateStore(),
        notesSource: CoordinatorNotesSource = CoordinatorNotesSource(),
        reminderSource: CoordinatorReminderSource? = nil,
        choreReminderSource: CoordinatorChoreReminderSource? = nil,
        recipeClassifier: (any RecipeClassifying)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> SyncCoordinator {
        SyncCoordinator(
            photoSource: photoSource,
            reminderSource: reminderSource ?? CoordinatorReminderSource(reminders: reminders),
            choreReminderSource: choreReminderSource,
            notesSource: notesSource,
            imageConverter: imageConverter,
            api: api,
            stateStore: state,
            recipeClassifier: recipeClassifier,
            calendar: calendar,
            now: now
        )
    }

    private func photoRecord(
        mappingID: UUID,
        appleAssetID: String,
        messageID: String
    ) -> PhotoSyncRecord {
        PhotoSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            destinationAlbumID: "album-1",
            appleAssetID: appleAssetID,
            renderedHash: "hash-\(appleAssetID)",
            skylightMessageID: messageID,
            skylightAlbumIDs: ["album-1"],
            lastSyncedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func reminderRecordFor(
        mappingID: UUID,
        appleID: String,
        itemID: String
    ) -> ReminderSyncRecord {
        ReminderSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            skylightListID: "remote-list",
            appleReminderID: appleID,
            appleExternalID: nil,
            skylightItemID: itemID,
            lastAppleModifiedAt: Date(timeIntervalSince1970: 100),
            lastSkylightModifiedAt: Date(timeIntervalSince1970: 100),
            contentFingerprint: "fingerprint",
            lastSyncedTitle: "Item",
            lastSyncedCompleted: false
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

    @Test("Automatic mode classifies a new recipe and decorates its title")
    func automaticModeClassifiesNewRecipe() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        let api = CoordinatorAPIStub()
        await api.configureRecipes([])
        await api.configureMealCategories(breakfastAndDinnerCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore()
        let classifier = StubRecipeClassifier(
            result: RecipeClassification(categoryLabel: "Dinner", emoji: "🌮")
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource,
            recipeClassifier: classifier
        )

        let summary = try await coordinator.sync(configuration: configuredRecipes())
        let requests = await api.recipeRequests
        let persisted = try await state.loadSyncState()

        #expect(summary.recipes.applied == 1)
        #expect(requests.first?.summary == "🌮 Tacos")
        #expect(requests.first?.mealCategoryID == "category-dinner")
        #expect(persisted.notes.first?.autoCategoryID == "category-dinner")
        #expect(persisted.notes.first?.autoEmoji == "🌮")
    }

    @Test("An unchanged recipe gets a one-time classification retrofit")
    func unchangedRecipeGetsClassificationRetrofit() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        var initial = SyncState()
        initial.notes = [recipeSyncRecord(
            noteID: "note-1",
            contentHash: sha(plaintext),
            skylightID: "recipe-1",
            remoteRevision: "rev-1"
        )]
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            remoteRecipe(id: "recipe-1", title: "Tacos", description: "", updatedAt: "rev-1")
        ])
        await api.configureMealCategories(breakfastAndDinnerCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore(state: initial)
        let classifier = StubRecipeClassifier(
            result: RecipeClassification(categoryLabel: "Dinner", emoji: "🌮")
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource,
            recipeClassifier: classifier
        )

        let first = try await coordinator.sync(configuration: configuredRecipes())
        let requests = await api.recipeRequests
        let persisted = try await state.loadSyncState()

        #expect(first.recipes.applied == 1)
        #expect(requests.last?.summary == "🌮 Tacos")
        #expect(requests.last?.mealCategoryID == "category-dinner")
        #expect(persisted.notes.first?.autoCategoryID == "category-dinner")

        // The retrofit is one-time: a second sync plans nothing.
        let second = try await coordinator.sync(configuration: configuredRecipes())
        #expect(second.recipes.planned == 0)
    }

    @Test("A fallback category assignment is not cached as a classification")
    func fallbackCategoryIsNotCached() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        let api = CoordinatorAPIStub()
        await api.configureRecipes([])
        await api.configureMealCategories(breakfastAndDinnerCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore()
        // The classifier is present but returns nothing, standing in for a
        // model call that failed; the push falls back to the first category.
        let classifier = StubRecipeClassifier(result: nil)
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource,
            recipeClassifier: classifier
        )

        _ = try await coordinator.sync(configuration: configuredRecipes())
        let requests = await api.recipeRequests
        let persisted = try await state.loadSyncState()

        #expect(requests.first?.mealCategoryID == "category-breakfast")
        #expect(persisted.notes.first?.autoCategoryID == nil)
    }

    @Test("A recipe stuck in the cached fallback category is reclassified once")
    func fallbackCachedCategoryIsRepairedAndReclassified() async throws {
        let plaintext = "Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        var initial = SyncState()
        // A pre-1.4.1 push cached the fallback (first) category as if the
        // model chose it, so the retrofit never fired.
        initial.notes = [recipeSyncRecord(
            noteID: "note-1",
            contentHash: sha(plaintext),
            skylightID: "recipe-1",
            remoteRevision: "rev-1",
            autoCategoryID: "category-breakfast",
            autoEmoji: "🌮"
        )]
        let api = CoordinatorAPIStub()
        await api.configureRecipes([
            remoteRecipe(id: "recipe-1", title: "Tacos", description: "", updatedAt: "rev-1")
        ])
        await api.configureMealCategories(breakfastAndDinnerCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore(state: initial)
        let classifier = StubRecipeClassifier(
            result: RecipeClassification(categoryLabel: "Dinner", emoji: "🌮")
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource,
            recipeClassifier: classifier
        )

        let first = try await coordinator.sync(configuration: configuredRecipes())
        let requests = await api.recipeRequests
        let persisted = try await state.loadSyncState()

        #expect(first.recipes.applied == 1)
        #expect(requests.last?.mealCategoryID == "category-dinner")
        #expect(persisted.notes.first?.autoCategoryID == "category-dinner")
        #expect(persisted.recipeFallbackCacheClearedFrameIDs.contains("frame-1"))

        // The repair is one-time: the reclassified category survives the
        // next sync even though it now matches nothing new.
        let second = try await coordinator.sync(configuration: configuredRecipes())
        #expect(second.recipes.planned == 0)
    }

    @Test("A classified recipe title that already has an emoji is left alone")
    func emojiTitlesAreNotDoubleDecorated() async throws {
        let plaintext = "🌮 Tacos\n\nIngredients\n- Shells\n\nInstructions\n1. Fill"
        let note = recipeNote(id: "note-1", plaintext: plaintext)
        let api = CoordinatorAPIStub()
        await api.configureRecipes([])
        await api.configureMealCategories(breakfastAndDinnerCategories)
        let notesSource = CoordinatorNotesSource(notes: [note])
        let state = CoordinatorStateStore()
        let classifier = StubRecipeClassifier(
            result: RecipeClassification(categoryLabel: "Dinner", emoji: "🥑")
        )
        let coordinator = makeCoordinator(
            api: api,
            reminders: [],
            state: state,
            notesSource: notesSource,
            recipeClassifier: classifier
        )

        _ = try await coordinator.sync(configuration: configuredRecipes())
        let requests = await api.recipeRequests

        #expect(requests.first?.summary == "🌮 Tacos")
        #expect(requests.first?.mealCategoryID == "category-dinner")
    }

    private var breakfastAndDinnerCategories: [SkylightResource<SkylightMealCategoryAttributes>] {
        [
            SkylightResource(
                id: "category-breakfast",
                attributes: SkylightMealCategoryAttributes(label: "Breakfast", color: nil)
            ),
            SkylightResource(
                id: "category-dinner",
                attributes: SkylightMealCategoryAttributes(label: "Dinner", color: nil)
            )
        ]
    }

    private func configuredRecipes(dryRun: Bool = false) -> AppConfiguration {
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = dryRun
        configuration.recipeSelection.folderID = "folder-1"
        configuration.recipeSelection.folderTitle = "Recipes"
        configuration.recipeSelection.direction = .twoWay
        configuration.recipeSelection.enabled = true
        return configuration
    }

    private var mealCategories: [SkylightResource<SkylightMealCategoryAttributes>] {
        [SkylightResource(
            id: "category-1",
            attributes: SkylightMealCategoryAttributes(label: "Dinner", color: nil)
        )]
    }

    private func recipeNote(id: String, plaintext: String) -> AppleNoteSnapshot {
        AppleNoteSnapshot(
            id: id,
            folderID: "folder-1",
            title: plaintext.components(separatedBy: "\n").first ?? "",
            bodyHTML: "",
            plaintext: plaintext,
            creationDate: Date(timeIntervalSince1970: 100),
            modificationDate: Date(timeIntervalSince1970: 600),
            isPasswordProtected: false,
            isShared: false,
            attachments: []
        )
    }

    private func recipeSyncRecord(
        noteID: String,
        contentHash: String,
        skylightID: String,
        remoteRevision: String,
        autoCategoryID: String? = nil,
        autoEmoji: String? = nil
    ) -> NoteSyncRecord {
        NoteSyncRecord(
            kind: .recipes,
            frameID: "frame-1",
            appleNoteID: noteID,
            contentHash: contentHash,
            skylightID: skylightID,
            lastSyncedAt: Date(timeIntervalSince1970: 100),
            lastAppleModifiedAt: Date(timeIntervalSince1970: 100),
            lastSkylightUpdatedAt: remoteRevision,
            autoCategoryID: autoCategoryID,
            autoEmoji: autoEmoji
        )
    }

    private func remoteRecipe(
        id: String,
        title: String,
        description: String?,
        ingredients: [String] = [],
        url: String? = nil,
        updatedAt: String
    ) -> SkylightResource<SkylightRecipeAttributes> {
        SkylightResource(
            id: id,
            attributes: SkylightRecipeAttributes(
                summary: title,
                description: description,
                ingredients: ingredients,
                url: url,
                imageURL: nil,
                createdAt: nil,
                updatedAt: updatedAt
            )
        )
    }

    private func sha(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
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

    private func remoteReminderList() -> SkylightResource<SkylightListAttributes> {
        SkylightResource(
            id: "remote-list",
            attributes: SkylightListAttributes(
                label: "Groceries",
                color: "#2178AF",
                kind: .shopping,
                hideOnDevice: nil
            )
        )
    }

    private func remoteReminderItem(
        id: String,
        title: String
    ) -> SkylightResource<SkylightListItemAttributes> {
        SkylightResource(
            id: id,
            attributes: SkylightListItemAttributes(
                label: title,
                status: .pending,
                section: nil,
                position: nil
            )
        )
    }

    private func recurringReminder(
        id: String,
        title: String,
        modifiedAt: Date = Date(timeIntervalSince1970: 200)
    ) -> AppleReminderSnapshot {
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
            modificationDate: modifiedAt,
            hasRecurrenceRules: true
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
    let collections: [String: [ApplePhotoAssetSnapshot]]
    let missingCollectionIDs: Set<String>
    private(set) var renderCount = 0

    init(
        assets: [ApplePhotoAssetSnapshot] = [],
        collections: [String: [ApplePhotoAssetSnapshot]] = [:],
        missingCollectionIDs: Set<String> = []
    ) {
        self.assets = assets
        self.collections = collections
        self.missingCollectionIDs = missingCollectionIDs
    }

    func syncPhotoCollections() async throws -> [ApplePhotoCollectionSnapshot] { [] }
    func syncPhotoAssets(in collectionID: String) async throws -> [ApplePhotoAssetSnapshot] {
        if missingCollectionIDs.contains(collectionID) {
            throw ApplePhotoLibraryError.collectionNotFound(collectionID)
        }
        return collections[collectionID] ?? assets
    }
    func syncPhotoAssets(withIDs assetIDs: [String]) async throws -> [ApplePhotoAssetSnapshot] { [] }
    func syncRenderedPhoto(withID assetID: String, maximumLongEdge: Int) async throws -> AppleRenderedPhoto {
        renderCount += 1
        let pool = assets + collections.values.flatMap { $0 }
        guard let asset = pool.first(where: { $0.id == assetID }),
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
    private(set) var reminders: [AppleReminderSnapshot]
    private(set) var createdReminders: [AppleReminderSnapshot] = []
    private(set) var updatedReminders: [AppleReminderSnapshot] = []
    private(set) var removedReminderIDs: [String] = []
    private(set) var listTitle: String
    private(set) var listColorHex: String?
    private let removalError: (any Error)?
    private let allowsCreation: Bool
    private let allowsUpdate: Bool
    private let missingListIDs: Set<String>
    private var nextCreatedReminderNumber = 1

    init(
        reminders: [AppleReminderSnapshot],
        listTitle: String = "Groceries",
        listColorHex: String? = "#2178AF",
        removalError: (any Error)? = nil,
        allowsCreation: Bool = false,
        allowsUpdate: Bool = false,
        missingListIDs: Set<String> = []
    ) {
        self.reminders = reminders
        self.listTitle = listTitle
        self.listColorHex = listColorHex
        self.removalError = removalError
        self.allowsCreation = allowsCreation
        self.allowsUpdate = allowsUpdate
        self.missingListIDs = missingListIDs
    }

    func syncReminderList(withID listID: String) throws -> AppleReminderListSnapshot {
        if missingListIDs.contains(listID) {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        return AppleReminderListSnapshot(
            id: listID,
            title: listTitle,
            colorHex: listColorHex,
            sourceID: "source-1",
            sourceTitle: "iCloud",
            allowsContentModifications: true
        )
    }

    func syncUpdateReminderList(
        withID listID: String,
        title: String?,
        colorHex: String?
    ) throws -> AppleReminderListSnapshot {
        if let title {
            listTitle = title
        }
        if let colorHex {
            listColorHex = colorHex
        }
        return try syncReminderList(withID: listID)
    }

    func syncReminders(in listID: String) async throws -> [AppleReminderSnapshot] {
        if missingListIDs.contains(listID) {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        return reminders
    }
    func syncCreateReminder(in listID: String, draft: AppleReminderDraft) async throws -> AppleReminderSnapshot {
        guard allowsCreation else { throw CoordinatorStubError.unexpectedCall }
        let reminder = AppleReminderSnapshot(
            id: "created-reminder-\(nextCreatedReminderNumber)",
            externalID: nil,
            listID: listID,
            listTitle: listTitle,
            title: draft.title,
            notes: draft.notes,
            url: draft.url,
            isCompleted: draft.isCompleted,
            completionDate: nil,
            startDateComponents: draft.startDateComponents,
            dueDateComponents: draft.dueDateComponents,
            priority: draft.priority,
            creationDate: Date(timeIntervalSince1970: 300),
            modificationDate: Date(timeIntervalSince1970: 300),
            hasRecurrenceRules: false
        )
        nextCreatedReminderNumber += 1
        reminders.append(reminder)
        createdReminders.append(reminder)
        return reminder
    }
    func syncUpdateReminder(withID reminderID: String, patch: AppleReminderPatch) async throws -> AppleReminderSnapshot {
        guard allowsUpdate,
              let index = reminders.firstIndex(where: { $0.id == reminderID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        let existing = reminders[index]
        let updated = AppleReminderSnapshot(
            id: existing.id,
            externalID: existing.externalID,
            listID: existing.listID,
            listTitle: existing.listTitle,
            title: patch.title ?? existing.title,
            notes: existing.notes,
            url: existing.url,
            isCompleted: patch.isCompleted ?? existing.isCompleted,
            completionDate: existing.completionDate,
            startDateComponents: existing.startDateComponents,
            dueDateComponents: existing.dueDateComponents,
            priority: patch.priority ?? existing.priority,
            creationDate: existing.creationDate,
            modificationDate: Date(timeIntervalSince1970: 400),
            hasRecurrenceRules: existing.hasRecurrenceRules
        )
        reminders[index] = updated
        updatedReminders.append(updated)
        return updated
    }
    func syncRemoveReminder(withID reminderID: String) async throws {
        if let removalError {
            throw removalError
        }
        removedReminderIDs.append(reminderID)
    }
}

@MainActor
private final class CoordinatorChoreReminderSource: ChoreReminderSource {
    private var reminders: [ChoreReminderSnapshot] = []
    private(set) var createdReminders: [ChoreReminderSnapshot] = []
    private(set) var removedReminderIDs: [String] = []
    private(set) var deletedListIDs: [String] = []
    private let listDeletionError: (any Error)?
    private var nextID = 1

    init(
        reminders: [ChoreReminderSnapshot] = [],
        listDeletionError: (any Error)? = nil
    ) {
        self.reminders = reminders
        self.listDeletionError = listDeletionError
    }

    func syncReminderLists() throws -> [AppleReminderListSnapshot] {
        [AppleReminderListSnapshot(
            id: "list-1",
            title: "Oliver Chores",
            sourceID: "source-1",
            sourceTitle: "iCloud",
            allowsContentModifications: true
        )]
    }

    func syncCreateReminderList(named title: String) throws -> AppleReminderListSnapshot {
        AppleReminderListSnapshot(
            id: "created-list",
            title: title,
            sourceID: "source-1",
            sourceTitle: "iCloud",
            allowsContentModifications: true
        )
    }

    func syncChoreReminders(
        in listID: String,
        memberKey: String
    ) async throws -> [ChoreReminderSnapshot] {
        reminders.filter { $0.listID == listID }
    }

    func syncCreateChoreReminder(
        in listID: String,
        draft: ChoreReminderDraft,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        let snapshot = ChoreReminderSnapshot(
            id: "apple-chore-\(nextID)",
            listID: listID,
            memberKey: memberKey,
            title: draft.title,
            notes: draft.notes,
            isCompleted: false,
            dueDate: draft.dueDate,
            recurrence: draft.recurrence,
            recurrenceUnsupported: false,
            modifiedAt: Date(timeIntervalSince1970: 500)
        )
        nextID += 1
        reminders.append(snapshot)
        createdReminders.append(snapshot)
        return snapshot
    }

    func syncUpdateChoreReminder(
        withID reminderID: String,
        patch: ChoreReminderPatch,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        guard let index = reminders.firstIndex(where: { $0.id == reminderID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        let old = reminders[index]
        let updated = ChoreReminderSnapshot(
            id: old.id,
            listID: old.listID,
            memberKey: memberKey,
            title: patch.title,
            notes: patch.notes,
            isCompleted: old.isCompleted,
            dueDate: patch.dueDate,
            recurrence: patch.replaceRecurrence ? patch.recurrence : old.recurrence,
            recurrenceUnsupported: false,
            modifiedAt: Date(timeIntervalSince1970: 600)
        )
        reminders[index] = updated
        return updated
    }

    func syncSetChoreReminderCompletion(
        withID reminderID: String,
        completed: Bool,
        dueDate: Date?,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        guard let index = reminders.firstIndex(where: { $0.id == reminderID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        let old = reminders[index]
        let rolledDate = completed && old.recurrence != nil
            ? old.dueDate.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }
            : (dueDate ?? old.dueDate)
        let updated = ChoreReminderSnapshot(
            id: old.id, listID: old.listID, memberKey: memberKey,
            title: old.title, notes: old.notes,
            isCompleted: completed && old.recurrence == nil,
            dueDate: rolledDate, recurrence: old.recurrence,
            recurrenceUnsupported: old.recurrenceUnsupported,
            modifiedAt: Date(timeIntervalSince1970: 700)
        )
        reminders[index] = updated
        return updated
    }

    func syncMoveChoreReminder(
        withID reminderID: String,
        toListID listID: String,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        guard let index = reminders.firstIndex(where: { $0.id == reminderID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        let old = reminders[index]
        let updated = ChoreReminderSnapshot(
            id: old.id, listID: listID, memberKey: memberKey,
            title: old.title, notes: old.notes, isCompleted: old.isCompleted,
            dueDate: old.dueDate, recurrence: old.recurrence,
            recurrenceUnsupported: old.recurrenceUnsupported,
            modifiedAt: Date(timeIntervalSince1970: 600)
        )
        reminders[index] = updated
        return updated
    }

    func syncRemoveChoreReminder(withID reminderID: String) throws {
        reminders.removeAll { $0.id == reminderID }
        removedReminderIDs.append(reminderID)
    }

    func syncDeleteReminderListIfEmpty(withID listID: String) async throws -> Bool {
        guard !reminders.contains(where: { $0.listID == listID }) else { return false }
        if let listDeletionError { throw listDeletionError }
        deletedListIDs.append(listID)
        return true
    }
}

private actor CoordinatorNotesSource: NotesSyncSource {
    private var notes: [AppleNoteSnapshot]
    private let attachmentCounts: [String: Int]
    private(set) var createdBodies: [String] = []
    private(set) var updatedBodiesByNoteID: [String: String] = [:]
    private(set) var trashedNoteIDs: [String] = []
    private var nextNoteNumber = 1

    init(notes: [AppleNoteSnapshot] = [], attachmentCounts: [String: Int] = [:]) {
        self.notes = notes
        self.attachmentCounts = attachmentCounts
    }

    func syncNoteSummaries(inFolderID folderID: String) async throws -> [AppleNoteSummarySnapshot] {
        notes
            .filter { $0.folderID == folderID }
            .map {
                AppleNoteSummarySnapshot(
                    id: $0.id,
                    folderID: $0.folderID,
                    title: $0.title,
                    creationDate: $0.creationDate,
                    modificationDate: $0.modificationDate,
                    isPasswordProtected: $0.isPasswordProtected,
                    isShared: $0.isShared,
                    attachmentCount: attachmentCounts[$0.id] ?? 0
                )
            }
    }

    func syncNote(withID noteID: String, inFolderID folderID: String) async throws -> AppleNoteSnapshot {
        guard let note = notes.first(where: { $0.id == noteID && $0.folderID == folderID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        return note
    }

    func syncCreateNote(inFolderID folderID: String, bodyHTML: String) async throws -> String {
        let noteID = "note-created-\(nextNoteNumber)"
        nextNoteNumber += 1
        createdBodies.append(bodyHTML)
        notes.append(Self.note(id: noteID, folderID: folderID, bodyHTML: bodyHTML))
        return noteID
    }

    func syncUpdateNote(
        withID noteID: String,
        inFolderID folderID: String,
        bodyHTML: String
    ) async throws {
        guard let index = notes.firstIndex(where: { $0.id == noteID && $0.folderID == folderID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        updatedBodiesByNoteID[noteID] = bodyHTML
        notes[index] = Self.note(id: noteID, folderID: folderID, bodyHTML: bodyHTML)
    }

    func syncTrashNote(withID noteID: String, inFolderID folderID: String) async throws {
        trashedNoteIDs.append(noteID)
        notes.removeAll { $0.id == noteID }
    }

    private static func note(id: String, folderID: String, bodyHTML: String) -> AppleNoteSnapshot {
        let plaintext = plaintext(fromBodyHTML: bodyHTML)
        return AppleNoteSnapshot(
            id: id,
            folderID: folderID,
            title: plaintext.components(separatedBy: "\n").first ?? "",
            bodyHTML: bodyHTML,
            plaintext: plaintext,
            creationDate: Date(timeIntervalSince1970: 500),
            modificationDate: Date(timeIntervalSince1970: 500),
            isPasswordProtected: false,
            isShared: false,
            attachments: []
        )
    }

    // Approximates how Apple Notes renders bridge-written HTML back to the
    // plaintext the parser reads on the next sync cycle.
    private static func plaintext(fromBodyHTML body: String) -> String {
        body
            .replacingOccurrences(of: "<div><br></div>", with: "\u{0}")
            .replacingOccurrences(of: "</div>", with: "\n")
            .replacingOccurrences(of: "<div>", with: "")
            .replacingOccurrences(of: "</h1>", with: "\n")
            .replacingOccurrences(of: "<h1>", with: "")
            .replacingOccurrences(of: "</h2>", with: "\n")
            .replacingOccurrences(of: "<h2>", with: "")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<li>", with: "")
            .replacingOccurrences(of: "<ul>", with: "")
            .replacingOccurrences(of: "</ul>", with: "")
            .replacingOccurrences(of: "<ol>", with: "")
            .replacingOccurrences(of: "</ol>", with: "")
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
            .replacingOccurrences(of: "\u{0}", with: "\n")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .newlines)
    }
}

private actor CoordinatorImageConverter: SyncImageConverting {
    let convertedAssetID: String?
    // Dedup tags carry a 12-character hex prefix of this hash, so tests that
    // exercise tag matching need hex; the default keeps older tests readable.
    let sha256: String
    let sha256ByAssetID: [String: String]
    private var failuresBeforeSuccess: Int

    init(
        convertedAssetID: String? = nil,
        sha256: String = "rendered-hash",
        sha256ByAssetID: [String: String] = [:],
        failuresBeforeSuccess: Int = 0
    ) {
        self.convertedAssetID = convertedAssetID
        self.sha256 = sha256
        self.sha256ByAssetID = sha256ByAssetID
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func syncConvert(
        _ renderedPhoto: AppleRenderedPhoto,
        options: AppleImageConversionOptions
    ) async throws -> AppleConvertedImage {
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw CoordinatorStubError.unexpectedCall
        }
        guard let convertedAssetID else {
            throw CoordinatorStubError.unexpectedCall
        }
        return AppleConvertedImage(
            assetID: convertedAssetID,
            data: Data([0x01]),
            typeIdentifier: "public.jpeg",
            pixelWidth: 1,
            pixelHeight: 1,
            sha256: sha256ByAssetID[renderedPhoto.asset.id] ?? sha256
        )
    }
}

private actor CoordinatorStateStore: SyncStatePersisting {
    private var state: SyncState
    private(set) var saveCount = 0

    init(state: SyncState = SyncState()) {
        self.state = state
    }

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
    var recipeCollections = 0
    var createdRecipes = 0
    var updatedRecipes = 0
    var deletedRecipes = 0
    var createdChores = 0
}

private actor CoordinatorAPIStub: SkylightSyncAPI {
    private var calls = CoordinatorAPICalls()
    private var lists: [SkylightResource<SkylightListAttributes>] = []
    private var listItems: [SkylightResource<SkylightListItemAttributes>] = []
    private var recipes: [SkylightResource<SkylightRecipeAttributes>] = []
    private var mealCategories: [SkylightResource<SkylightMealCategoryAttributes>] = []
    private var chores: [SkylightResource<SkylightChoreAttributes>] = []
    private var choreUpdatesAllowed = false
    private var listItemUpdatesAllowed = false
    private var cleanupError: (any Error)?
    private(set) var createdMealCount = 0
    private(set) var deletedMealIDs: [String] = []
    private var albums: [SkylightResource<SkylightAlbumAttributes>] = []
    private var albumCreationAllowed = false
    private(set) var createdAlbumTitles: [String] = []
    private(set) var completedChoreSeriesIDs: [String] = []
    private(set) var choreCompletionRequests: [SkylightChoreCompletionRequest] = []
    private(set) var choreListRequests: [(before: String?, after: String?)] = []
    private(set) var deletedChoreRequests: [(choreID: String, applyToAll: Bool)] = []
    private(set) var choreRequests: [SkylightChoreRequest] = []
    private(set) var updatedRecipeIDs: [String] = []
    private(set) var deletedRecipeIDs: [String] = []
    private(set) var recipeRequests: [SkylightRecipeRequest] = []
    private(set) var listUpdateRequests: [SkylightListRequest] = []
    private(set) var messageCaptionUpdates: [String] = []

    func snapshot() -> CoordinatorAPICalls { calls }
    func allowListItemUpdates() { listItemUpdatesAllowed = true }
    func configureCleanupError(_ error: (any Error)?) { cleanupError = error }


    func configureLists(
        _ lists: [SkylightResource<SkylightListAttributes>],
        items: [SkylightResource<SkylightListItemAttributes>]
    ) {
        self.lists = lists
        listItems = items
    }

    func configureRecipes(_ recipes: [SkylightResource<SkylightRecipeAttributes>]) {
        self.recipes = recipes
    }

    func configureMealCategories(
        _ categories: [SkylightResource<SkylightMealCategoryAttributes>]
    ) {
        mealCategories = categories
    }

    func configureChores(_ chores: [SkylightResource<SkylightChoreAttributes>]) {
        self.chores = chores
    }

    func configureChoreUpdatesAllowed(_ allowed: Bool) {
        choreUpdatesAllowed = allowed
    }

    func configureAlbums(_ albums: [SkylightResource<SkylightAlbumAttributes>]) {
        self.albums = albums
    }

    func configureAlbumCreationAllowed(_ allowed: Bool) {
        albumCreationAllowed = allowed
    }

    func listAllChores(frameID: String) async throws -> [SkylightResource<SkylightChoreAttributes>] {
        chores
    }

    func listChores(
        frameID: String,
        before: String?,
        after: String?,
        includeLate: Bool?,
        filter: String?
    ) async throws -> [SkylightResource<SkylightChoreAttributes>] {
        choreListRequests.append((before, after))
        return chores
    }

    func createChore(
        frameID: String,
        request: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes> {
        calls.createdChores += 1
        choreRequests.append(request)
        let id = "remote-chore-\(calls.createdChores)"
        let created = SkylightResource(
            id: id,
            attributes: SkylightChoreAttributes(
                summary: request.summary,
                description: request.description,
                status: request.status,
                start: request.start,
                startTime: request.startTime,
                rewardPoints: request.rewardPoints,
                recurring: request.recurring,
                recurringUntil: request.recurringUntil,
                recurrenceSet: request.recurrenceSet,
                upForGrabs: request.upForGrabs,
                emojiIcon: request.emojiIcon,
                routine: request.routine,
                position: request.position,
                series: id
            )
        )
        chores.append(created)
        return created
    }

    func updateChore(frameID: String, choreID: String, request: SkylightChoreRequest) async throws -> SkylightResource<SkylightChoreAttributes> {
        guard choreUpdatesAllowed,
              let index = chores.firstIndex(where: { $0.id == choreID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        choreRequests.append(request)
        var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(chores[index])) as? [String: Any])
        var attributes = try #require(encoded["attributes"] as? [String: Any])
        let changes = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        attributes.merge(changes) { _, new in new }
        encoded["attributes"] = attributes
        let updated = try JSONDecoder().decode(SkylightResource<SkylightChoreAttributes>.self,
                                               from: JSONSerialization.data(withJSONObject: encoded))
        chores[index] = updated
        return updated
    }

    func deleteChore(frameID: String, choreID: String, applyToAll: Bool) async throws {
        deletedChoreRequests.append((choreID: choreID, applyToAll: applyToAll))
        chores.removeAll { $0.id == choreID }
    }

    func setChoreCompletion(
        frameID: String,
        seriesID: String,
        request: SkylightChoreCompletionRequest
    ) async throws {
        choreCompletionRequests.append(request)
        if let index = chores.firstIndex(where: { $0.id == seriesID }) {
            var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(chores[index])) as? [String: Any])
            var attributes = try #require(encoded["attributes"] as? [String: Any])
            attributes["status"] = request.status.rawValue
            encoded["attributes"] = attributes
            chores[index] = try JSONDecoder().decode(
                SkylightResource<SkylightChoreAttributes>.self,
                from: JSONSerialization.data(withJSONObject: encoded)
            )
        }
        if request.status == .complete {
            completedChoreSeriesIDs.append(seriesID)
        }
    }

    func listLists(frameID: String) async throws -> SkylightListCollectionResponse {
        calls.listCollections += 1
        return SkylightListCollectionResponse(data: lists, included: nil)
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

    func updateList(
        frameID: String,
        listID: String,
        request: SkylightListRequest
    ) async throws -> SkylightResource<SkylightListAttributes> {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        listUpdateRequests.append(request)
        let existing = lists[index]
        let updated = SkylightResource(
            id: existing.id,
            attributes: SkylightListAttributes(
                label: request.label ?? existing.attributes.label,
                color: request.color ?? existing.attributes.color,
                kind: request.kind ?? existing.attributes.kind,
                hideOnDevice: request.hideOnDevice ?? existing.attributes.hideOnDevice
            )
        )
        lists[index] = updated
        return updated
    }

    func listListItems(
        frameID: String,
        listID: String
    ) async throws -> [SkylightResource<SkylightListItemAttributes>] { listItems }

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

    private(set) var deletedListItemIDs: [String] = []
    private(set) var deletedMessageIDs: [String] = []
    private(set) var removedFromAlbumMessageIDs: [String] = []
    private(set) var removedMessageRequests: [(
        frameID: String,
        albumIDs: [String],
        messageIDs: [String]
    )] = []
    private(set) var deletedListItemRequests: [(frameID: String, listID: String, itemID: String)] = []
    private(set) var deletedMessageRequests: [(frameID: String, messageID: String)] = []

    func updateListItem(frameID: String, listID: String, itemID: String, request: SkylightListItemRequest) async throws -> SkylightResource<SkylightListItemAttributes> {
        guard listItemUpdatesAllowed, let index = listItems.firstIndex(where: { $0.id == itemID }) else {
            throw CoordinatorStubError.unexpectedCall
        }
        let updated = SkylightResource(id: itemID, attributes: SkylightListItemAttributes(
            label: request.label, status: request.status, section: request.section, position: request.position
        ))
        listItems[index] = updated
        return updated
    }
    func deleteListItem(frameID: String, listID: String, itemID: String) async throws {
        deletedListItemIDs.append(itemID)
        deletedListItemRequests.append((frameID, listID, itemID))
    }
    func listAlbums(frameID: String) async throws -> [SkylightResource<SkylightAlbumAttributes>] {
        calls.albumCollections += 1
        return albums
    }
    func createAlbum(frameID: String, title: String) async throws -> SkylightResource<SkylightAlbumAttributes> {
        calls.createdAlbums += 1
        guard albumCreationAllowed else { throw CoordinatorStubError.unexpectedCall }
        createdAlbumTitles.append(title)
        let created = SkylightResource(
            id: "created-album",
            attributes: SkylightAlbumAttributes(
                title: title,
                messageCount: 0,
                createdAt: nil,
                updatedAt: nil
            )
        )
        albums.append(created)
        return created
    }
   private(set) var deletedAlbumIDs: [String] = []
   private var albumMessageIDsByAlbum: [String: [String]] = [:]
    private var albumMessageListFailure: (any Error)?
    private var albumMessagesByAlbum: [String: [String]] = [:]
    private var albumMessageCaptions: [String: String] = [:]
   func configureAlbumMessages(_ map: [String: [String]]) { albumMessageIDsByAlbum = map }
    func configureAlbumMessageListFailure(_ error: (any Error)?) {
        albumMessageListFailure = error
    }
    func configureAlbumMessagesWithCaptions(_ map: [String: [(id: String, caption: String?)]]) {
        for (albumID, entries) in map {
            albumMessagesByAlbum[albumID] = entries.map(\.id)
            for entry in entries {
                if let caption = entry.caption {
                    albumMessageCaptions[entry.id] = caption
                }
            }
        }
    }
   func deleteAlbum(frameID: String, albumID: String) async throws {
       deletedAlbumIDs.append(albumID)
   }
   func listAllAlbumMessageIDs(frameID: String, albumID: String) async throws -> [String] {
       if let albumMessageListFailure { throw albumMessageListFailure }
       return albumMessageIDsByAlbum[albumID] ?? []
   }
    func listAlbumMessages(frameID: String, albumID: String, page: Int?) async throws -> SkylightPhotoMessagesResponse {
        let messages = (albumMessagesByAlbum[albumID] ?? []).map { id in
            SkylightResource(
                id: id,
                attributes: SkylightPhotoMessageAttributes(
                    status: "downloaded",
                    assetType: "image",
                    createdAt: nil,
                    updatedAt: nil,
                    thumbnailURL: nil,
                    assetURL: nil,
                    senderID: nil,
                    caption: albumMessageCaptions[id]
                )
            )
        }
        return SkylightPhotoMessagesResponse(data: messages, meta: nil)
    }
   func requestUploadURL(ext: String, frameIDs: [String], caption: String?) async throws -> SkylightUploadURLAttributes {
        let messageID = "message-\(uploadCount + 1)"
        uploadedMessages.append((id: messageID, caption: caption))
        // SkylightUploadURLAttributes has no memberwise initializer (its
        // CodingKeys map snake_case fields), so build one through JSON.
        let payload = """
        {"url":"https://bridge-uploads.s3.amazonaws.com/presigned","message_ids":["\(messageID)"]}
        """
        return try JSONDecoder().decode(SkylightUploadURLAttributes.self, from: Data(payload.utf8))
    }
    private(set) var uploadCount = 0
    private(set) var uploadedMessages: [(id: String, caption: String?)] = []
    private(set) var addedToAlbumCalls: [(albumID: String, messageID: String)] = []
    func upload(data: Data, to presignedURL: URL, contentType: String) async throws {
        uploadCount += 1
    }
    func addMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws {
        for albumID in albumIDs {
            for messageID in messageIDs {
                addedToAlbumCalls.append((albumID, messageID))
                if !(albumMessagesByAlbum[albumID] ?? []).contains(messageID) {
                    albumMessagesByAlbum[albumID, default: []].append(messageID)
                }
                if let uploaded = uploadedMessages.first(where: { $0.id == messageID }),
                   let caption = uploaded.caption {
                    albumMessageCaptions[messageID] = caption
                }
            }
        }
    }
    func removeMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws {
        removedFromAlbumMessageIDs.append(contentsOf: messageIDs)
        removedMessageRequests.append((frameID, albumIDs, messageIDs))
    }
    func deleteMessage(frameID: String, messageID: String) async throws {
        if let failure = deleteMessageFailure {
            throw failure
        }
        deletedMessageIDs.append(messageID)
        deletedMessageRequests.append((frameID, messageID))
    }
    private var deleteMessageFailure: (any Error)?
    func configureDeleteMessageFailure(_ error: (any Error)?) {
        deleteMessageFailure = error
    }
    func updateMessageCaption(
        frameID: String,
        messageID: String,
        caption: String
    ) async throws -> SkylightResource<SkylightPhotoMessageAttributes> {
        messageCaptionUpdates.append(caption)
        return SkylightResource(
            id: messageID,
            attributes: SkylightPhotoMessageAttributes(
                status: "downloaded",
                assetType: "image",
                createdAt: nil,
                updatedAt: nil,
                thumbnailURL: nil,
                assetURL: nil,
                senderID: nil,
                caption: caption
            )
        )
    }
    func getMessage(frameID: String, messageID: String) async throws -> SkylightResource<SkylightPhotoMessageAttributes> {
        guard let message = uploadedMessages.first(where: { $0.id == messageID }) else {
            // The normal post-PUT processing window: not queryable yet.
            throw SkylightAPIError.httpStatus(code: 404, endpoint: "messages", body: "")
        }
        return SkylightResource(
            id: message.id,
            attributes: SkylightPhotoMessageAttributes(
                status: "downloaded",
                assetType: "image",
                createdAt: nil,
                updatedAt: nil,
                thumbnailURL: nil,
                assetURL: nil,
                senderID: nil,
                caption: message.caption
            )
        )
    }
    func listMessages(frameID: String, page: Int?, syncToken: String?, pageToken: String?) async throws -> SkylightPhotoMessagesResponse { throw CoordinatorStubError.unexpectedCall }
    func createRecipe(frameID: String, request: SkylightRecipeRequest) async throws -> SkylightResource<SkylightRecipeAttributes> {
        calls.createdRecipes += 1
        recipeRequests.append(request)
        return recipeResource(
            id: "recipe-created-\(calls.createdRecipes)",
            request: request,
            revision: "rev-create-\(calls.createdRecipes)"
        )
    }
    func updateRecipe(frameID: String, recipeID: String, request: SkylightRecipeRequest) async throws -> SkylightResource<SkylightRecipeAttributes> {
        calls.updatedRecipes += 1
        updatedRecipeIDs.append(recipeID)
        recipeRequests.append(request)
        let updated = recipeResource(
            id: recipeID,
            request: request,
            revision: "rev-update-\(calls.updatedRecipes)"
        )
        // Mirror the live API: later listRecipes calls return the new revision.
        if let index = recipes.firstIndex(where: { $0.id == recipeID }) {
            recipes[index] = updated
        }
        return updated
    }
    func listRecipes(frameID: String) async throws -> [SkylightResource<SkylightRecipeAttributes>] {
        calls.recipeCollections += 1
        return recipes
    }
    func deleteRecipe(frameID: String, recipeID: String, applyToSittings: Bool) async throws {
        if let cleanupError { throw cleanupError }
        calls.deletedRecipes += 1
        deletedRecipeIDs.append(recipeID)
        recipes.removeAll { $0.id == recipeID }
    }
    func listMealCategories(frameID: String) async throws -> [SkylightResource<SkylightMealCategoryAttributes>] { mealCategories }

    private func recipeResource(
        id: String,
        request: SkylightRecipeRequest,
        revision: String
    ) -> SkylightResource<SkylightRecipeAttributes> {
        SkylightResource(
            id: id,
            attributes: SkylightRecipeAttributes(
                summary: request.summary,
                description: request.description,
                ingredients: request.ingredients,
                url: request.url,
                imageURL: nil,
                createdAt: nil,
                updatedAt: revision
            )
        )
    }
    func createMealSitting(frameID: String, request: SkylightMealSittingRequest) async throws -> SkylightResource<SkylightMealSittingAttributes> {
        createdMealCount += 1
        return SkylightResource(id: "meal-\(createdMealCount)", attributes: SkylightMealSittingAttributes(
            summary: request.summary, description: request.description, note: request.note,
            date: request.date, addToGroceryList: request.addToGroceryList, rrule: nil
        ))
    }
    func updateMealInstance(frameID: String, mealID: String, instanceISO: String, request: SkylightMealInstanceUpdateRequest) async throws -> SkylightResource<SkylightMealSittingAttributes> { throw CoordinatorStubError.unexpectedCall }
    func deleteMealInstance(frameID: String, mealID: String, instanceISO: String, applyTo: String?) async throws {
        if let cleanupError { throw cleanupError }
        deletedMealIDs.append(mealID)
    }
}

private struct StubRecipeClassifier: RecipeClassifying {
    let result: RecipeClassification?
    var isAvailable: Bool { true }

    func classify(
        title: String,
        ingredients: [String],
        categoryLabels: [String]
    ) async -> RecipeClassification? {
        result
    }
}
