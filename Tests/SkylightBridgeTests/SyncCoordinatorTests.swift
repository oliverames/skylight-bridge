import CoreGraphics
import CryptoKit
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

    @Test("A bridge album that still holds photos is kept when the mapping is deleted")
    func purgePhotoMappingKeepsNonEmptyAlbum() async throws {
        let mappingID = UUID()
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

    private func makeCoordinator(
        api: CoordinatorAPIStub,
        reminders: [AppleReminderSnapshot],
        photoSource: CoordinatorPhotoSource = CoordinatorPhotoSource(),
        imageConverter: CoordinatorImageConverter = CoordinatorImageConverter(),
        state: CoordinatorStateStore = CoordinatorStateStore(),
        notesSource: CoordinatorNotesSource = CoordinatorNotesSource(),
        reminderSource: CoordinatorReminderSource? = nil,
        recipeClassifier: (any RecipeClassifying)? = nil
    ) -> SyncCoordinator {
        SyncCoordinator(
            photoSource: photoSource,
            reminderSource: reminderSource ?? CoordinatorReminderSource(reminders: reminders),
            notesSource: notesSource,
            imageConverter: imageConverter,
            api: api,
            stateStore: state,
            recipeClassifier: recipeClassifier
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
    private(set) var removedReminderIDs: [String] = []

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
        removedReminderIDs.append(reminderID)
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
}

private actor CoordinatorAPIStub: SkylightSyncAPI {
    private var calls = CoordinatorAPICalls()
    private var lists: [SkylightResource<SkylightListAttributes>] = []
    private var listItems: [SkylightResource<SkylightListItemAttributes>] = []
    private var recipes: [SkylightResource<SkylightRecipeAttributes>] = []
    private var mealCategories: [SkylightResource<SkylightMealCategoryAttributes>] = []
    private(set) var updatedRecipeIDs: [String] = []
    private(set) var deletedRecipeIDs: [String] = []
    private(set) var recipeRequests: [SkylightRecipeRequest] = []

    func snapshot() -> CoordinatorAPICalls { calls }

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

    func updateListItem(frameID: String, listID: String, itemID: String, request: SkylightListItemRequest) async throws -> SkylightResource<SkylightListItemAttributes> { throw CoordinatorStubError.unexpectedCall }
    func deleteListItem(frameID: String, listID: String, itemID: String) async throws {
        deletedListItemIDs.append(itemID)
    }
    func listAlbums(frameID: String) async throws -> [SkylightResource<SkylightAlbumAttributes>] {
        calls.albumCollections += 1
        return []
    }
    func createAlbum(frameID: String, title: String) async throws -> SkylightResource<SkylightAlbumAttributes> {
        calls.createdAlbums += 1
        throw CoordinatorStubError.unexpectedCall
    }
    private(set) var deletedAlbumIDs: [String] = []
    private var albumMessageIDsByAlbum: [String: [String]] = [:]
    func configureAlbumMessages(_ map: [String: [String]]) { albumMessageIDsByAlbum = map }
    func deleteAlbum(frameID: String, albumID: String) async throws {
        deletedAlbumIDs.append(albumID)
    }
    func listAllAlbumMessageIDs(frameID: String, albumID: String) async throws -> [String] {
        albumMessageIDsByAlbum[albumID] ?? []
    }
    func requestUploadURL(ext: String, frameIDs: [String], caption: String?) async throws -> SkylightUploadURLAttributes { throw CoordinatorStubError.unexpectedCall }
    func upload(data: Data, to presignedURL: URL, contentType: String) async throws { throw CoordinatorStubError.unexpectedCall }
    func addMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws { throw CoordinatorStubError.unexpectedCall }
    func removeMessages(frameID: String, albumIDs: [String], messageIDs: [String]) async throws {
        removedFromAlbumMessageIDs.append(contentsOf: messageIDs)
    }
    func deleteMessage(frameID: String, messageID: String) async throws {
        deletedMessageIDs.append(messageID)
    }
    func getMessage(frameID: String, messageID: String) async throws -> SkylightResource<SkylightPhotoMessageAttributes> { throw CoordinatorStubError.unexpectedCall }
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
    func createMealSitting(frameID: String, request: SkylightMealSittingRequest) async throws -> SkylightResource<SkylightMealSittingAttributes> { throw CoordinatorStubError.unexpectedCall }
    func updateMealInstance(frameID: String, mealID: String, instanceISO: String, request: SkylightMealInstanceUpdateRequest) async throws -> SkylightResource<SkylightMealSittingAttributes> { throw CoordinatorStubError.unexpectedCall }
    func deleteMealInstance(frameID: String, mealID: String, instanceISO: String, applyTo: String?) async throws { throw CoordinatorStubError.unexpectedCall }
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
