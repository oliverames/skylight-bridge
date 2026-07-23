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

        let summary = try await coordinator.sync(configuration: configuration)
        let captions = await api.messageCaptionUpdates
        let persisted = try await state.loadSyncState()

        #expect(summary.photos.applied == 1)
        #expect(captions == ["Backyard birthday"])
        #expect(persisted.photos.first?.lastSyncedCaption == "Backyard birthday")
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

    @Test("A rolled EventKit occurrence rebinds before completion is propagated")
    func rebindsRolledRecurringReminderIdentifier() async throws {
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
    }

    @Test("A stale completed recurring reminder rebinds to a new occurrence without duplicating")
    func rebindsStaleCompletedRecurringReminder() async throws {
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
            recurrence: ParsedRecurrenceRule(frequency: .daily),
            recurrenceUnsupported: false,
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
            recurrence: ParsedRecurrenceRule(frequency: .daily),
            recurrenceUnsupported: false,
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
        #expect(summary.chores.applied <= 1)
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
    private(set) var listTitle: String
    private(set) var listColorHex: String?

    init(
        reminders: [AppleReminderSnapshot],
        listTitle: String = "Groceries",
        listColorHex: String? = "#2178AF"
    ) {
        self.reminders = reminders
        self.listTitle = listTitle
        self.listColorHex = listColorHex
    }

    func syncReminderList(withID listID: String) throws -> AppleReminderListSnapshot {
        AppleReminderListSnapshot(
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

@MainActor
private final class CoordinatorChoreReminderSource: ChoreReminderSource {
    private var reminders: [ChoreReminderSnapshot] = []
    private(set) var createdReminders: [ChoreReminderSnapshot] = []
    private(set) var removedReminderIDs: [String] = []
    private(set) var deletedListIDs: [String] = []
    private var nextID = 1

    init(reminders: [ChoreReminderSnapshot] = []) {
        self.reminders = reminders
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
    var createdChores = 0
}

private actor CoordinatorAPIStub: SkylightSyncAPI {
    private var calls = CoordinatorAPICalls()
    private var lists: [SkylightResource<SkylightListAttributes>] = []
    private var listItems: [SkylightResource<SkylightListItemAttributes>] = []
    private var recipes: [SkylightResource<SkylightRecipeAttributes>] = []
    private var mealCategories: [SkylightResource<SkylightMealCategoryAttributes>] = []
    private var chores: [SkylightResource<SkylightChoreAttributes>] = []
    private var albums: [SkylightResource<SkylightAlbumAttributes>] = []
    private(set) var completedChoreSeriesIDs: [String] = []
    private(set) var choreCompletionRequests: [SkylightChoreCompletionRequest] = []
    private(set) var deletedChoreRequests: [(choreID: String, applyToAll: Bool)] = []
    private(set) var choreRequests: [SkylightChoreRequest] = []
    private(set) var updatedRecipeIDs: [String] = []
    private(set) var deletedRecipeIDs: [String] = []
    private(set) var recipeRequests: [SkylightRecipeRequest] = []
    private(set) var listUpdateRequests: [SkylightListRequest] = []
    private(set) var messageCaptionUpdates: [String] = []

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

    func configureChores(_ chores: [SkylightResource<SkylightChoreAttributes>]) {
        self.chores = chores
    }

    func configureAlbums(_ albums: [SkylightResource<SkylightAlbumAttributes>]) {
        self.albums = albums
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
        chores
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

    func updateChore(
        frameID: String,
        choreID: String,
        request: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes> {
        throw CoordinatorStubError.unexpectedCall
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

    func updateListItem(frameID: String, listID: String, itemID: String, request: SkylightListItemRequest) async throws -> SkylightResource<SkylightListItemAttributes> { throw CoordinatorStubError.unexpectedCall }
    func deleteListItem(frameID: String, listID: String, itemID: String) async throws {
        deletedListItemIDs.append(itemID)
    }
    func listAlbums(frameID: String) async throws -> [SkylightResource<SkylightAlbumAttributes>] {
        calls.albumCollections += 1
        return albums
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
