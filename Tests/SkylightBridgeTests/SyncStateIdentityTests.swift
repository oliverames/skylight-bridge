import Foundation
import SkylightBridgeShared
import Testing
@testable import SkylightBridge

@Suite(.serialized)
struct SyncStateIdentityTests {
    @Test("Deferred selected-photo changes preserve the latest user intent")
    func deferredSelectedPhotoChangesUseLatestIntent() {
        let mappingID = UUID()
        var pending = PendingSharedPhotoChanges()
        pending.record(
            mappingID: mappingID,
            additions: ["asset-added", "asset-toggled"],
            removals: ["asset-removed"]
        )
        pending.record(
            mappingID: mappingID,
            additions: ["asset-removed"],
            removals: ["asset-toggled"]
        )

        #expect(pending.additions[mappingID] == ["asset-added", "asset-removed"])
        #expect(pending.removals[mappingID] == ["asset-toggled"])
        #expect(
            pending.applying(
                to: ["asset-toggled"],
                mappingID: mappingID
            ) == ["asset-added", "asset-removed"]
        )

        var partiallyAcknowledged = PendingSharedPhotoChanges()
        partiallyAcknowledged.additions[mappingID] = ["asset-added"]
        pending.acknowledge(partiallyAcknowledged)
        #expect(pending.additions[mappingID] == ["asset-removed"])
        #expect(pending.removals[mappingID] == ["asset-toggled"])

        let published = pending
        pending.record(
            mappingID: mappingID,
            additions: ["asset-later"],
            removals: []
        )
        pending.acknowledge(published)

        #expect(pending.additions[mappingID] == ["asset-later"])
        #expect(pending.removals[mappingID] == nil)

        var original = PhotoMapping(name: "Original", sourceKind: .selectedPhotos)
        original.id = mappingID
        pending.recordPortableMapping(original)
        var publishedPortable = PendingSharedPhotoChanges()
        publishedPortable.portableMappings[mappingID] = original
        var latest = original
        latest.name = "Latest"
        latest.maximumLongEdge = 1_440
        pending.recordPortableMapping(latest)
        pending.acknowledge(publishedPortable)

        let reapplied = pending.applyingPortableFields(
            to: PhotoMapping(id: mappingID, name: "Remote", sourceKind: .selectedPhotos)
        )
        #expect(reapplied.name == "Latest")
        #expect(reapplied.maximumLongEdge == 1_440)
        #expect(pending.portableMappings[mappingID] == latest)

        pending.discard(mappingID: mappingID)
        #expect(pending.isEmpty)
    }

    @Test("Shared-state publishes wait for the full Cloud operation gate")
    @MainActor
    func sharedStatePublishWaitsForCloudOperationGate() async throws {
        let defaults = UserDefaults.standard
        let preferencesKey = "shared-preferences-v1"
        let installationKey = "cloud-installation-id"
        let previousPreferences = defaults.data(forKey: preferencesKey)
        let previousInstallationID = defaults.string(forKey: installationKey)
        defer {
            if let previousPreferences {
                defaults.set(previousPreferences, forKey: preferencesKey)
            } else {
                defaults.removeObject(forKey: preferencesKey)
            }
            if let previousInstallationID {
                defaults.set(previousInstallationID, forKey: installationKey)
            } else {
                defaults.removeObject(forKey: installationKey)
            }
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(.empty)
        let preferences = CountingPreferencesStore()
        let store = AppStore(
            persistence: persistence,
            sharedPreferencesStore: preferences
        )
        store.sharedCloudOperationInProgress = true

        let publish = Task { await store.publishSharediCloudState() }
        try await ContinuousClock().sleep(for: .milliseconds(150))

        #expect(await preferences.saveCount == 0)

        store.sharedCloudOperationInProgress = false
        #expect(await publish.value)
        #expect(await preferences.saveCount == 1)
    }

    @Test("A blocked retirement stops after the mapping is reactivated")
    @MainActor
    func stalePhotoRetirementStopsAfterReactivation() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testConfigurationStore(rootURL: directory)
        let selected = PhotoMapping(name: "Family", sourceKind: .selectedPhotos)
        var configuration = AppConfiguration.empty
        configuration.photoMappings = [selected]
        try persistence.saveConfiguration(configuration)
        let photoStore = RecordingPhotoMappingStore()
        let store = AppStore(
            persistence: persistence,
            sharedPreferencesStore: CountingPreferencesStore(),
            sharedPhotoMappingStore: photoStore
        )
        store.photosAuthorizationStatus = .denied
        store.sharedCloudOperationInProgress = true

        var localOnly = selected
        localOnly.sourceKind = .album
        #expect(store.savePhotoMapping(localOnly, triggerSync: false))
        let blockedRetirement = Task {
            await store.retireSharedPhotoMapping(selected)
        }
        try await ContinuousClock().sleep(for: .milliseconds(150))

        var reactivated = localOnly
        reactivated.sourceKind = .selectedPhotos
        #expect(store.savePhotoMapping(reactivated, triggerSync: false))
        #expect(!store.configuration.retiredPhotoMappingIDs.contains(selected.id))
        #expect(store.configuration.pendingPhotoMappingRetirements.isEmpty)

        store.sharedCloudOperationInProgress = false
        await blockedRetirement.value

        #expect(await photoStore.savedMappings().isEmpty)
    }

    @Test("Unresolved selected-photo identifiers remain pending and report failure")
    @MainActor
    func unresolvedSelectedPhotoIdentifiersRemainPending() async throws {
        let defaults = UserDefaults.standard
        let preferencesKey = "shared-preferences-v1"
        let installationKey = "cloud-installation-id"
        let previousPreferences = defaults.data(forKey: preferencesKey)
        let previousInstallationID = defaults.string(forKey: installationKey)
        defer {
            if let previousPreferences {
                defaults.set(previousPreferences, forKey: preferencesKey)
            } else {
                defaults.removeObject(forKey: preferencesKey)
            }
            if let previousInstallationID {
                defaults.set(previousInstallationID, forKey: installationKey)
            } else {
                defaults.removeObject(forKey: installationKey)
            }
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(.empty)
        let store = AppStore(
            persistence: persistence,
            sharedPreferencesStore: CountingPreferencesStore()
        )
        let mappingID = UUID()
        store.photosAuthorizationStatus = .denied
        store.pendingSharedPhotoChanges.record(
            mappingID: mappingID,
            additions: ["unresolved-asset"],
            removals: []
        )

        let published = await store.publishSharediCloudState()

        #expect(!published)
        #expect(store.pendingSharedPhotoChanges.additions[mappingID] == ["unresolved-asset"])
        #expect(store.activity.contains { $0.message.contains("still pending") })
    }

    @Test("Frame-scoped sync records have distinct identities")
    func frameScopedRecordsHaveDistinctIdentities() {
        let mappingID = UUID()
        let photoOne = PhotoSyncRecord(
            mappingID: mappingID, frameID: "frame-1", appleAssetID: "asset-1",
            renderedHash: "hash", skylightMessageID: "message-1",
            skylightAlbumIDs: [], lastSyncedAt: .distantPast
        )
        let photoTwo = PhotoSyncRecord(
            mappingID: mappingID, frameID: "frame-2", appleAssetID: "asset-1",
            renderedHash: "hash", skylightMessageID: "message-2",
            skylightAlbumIDs: [], lastSyncedAt: .distantPast
        )
        let reminderOne = reminderRecord(mappingID: mappingID, frameID: "frame-1")
        let reminderTwo = reminderRecord(mappingID: mappingID, frameID: "frame-2")
        let albumOne = PhotoAlbumRecord(
            mappingID: mappingID, frameID: "frame-1", albumID: "album-1"
        )
        let albumTwo = PhotoAlbumRecord(
            mappingID: mappingID, frameID: "frame-2", albumID: "album-1"
        )
        let destinationOne = PhotoDestinationSyncRecord(
            mappingID: mappingID, frameID: "frame-1", albumID: "album-1"
        )
        let destinationTwo = PhotoDestinationSyncRecord(
            mappingID: mappingID, frameID: "frame-2", albumID: "album-1"
        )

        #expect(photoOne.id != photoTwo.id)
        #expect(reminderOne.id != reminderTwo.id)
        #expect(albumOne.id != albumTwo.id)
        #expect(destinationOne.id != destinationTwo.id)
    }

    @Test("Older configurations decode with no retired photo mappings")
    func retiredMappingSetIsBackwardCompatible() throws {
        let data = Data(#"{"photoMappings":[]}"#.utf8)

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        #expect(configuration.retiredPhotoMappingIDs.isEmpty)
        #expect(configuration.pendingPhotoMappingRetirements.isEmpty)
        #expect(configuration.recipeDestinationCategoryIDsByFrame.isEmpty)
        #expect(configuration.mealDestinationCategoryIDsByFrame.isEmpty)
        #expect(configuration.photoDestinationAlbumIDsByFrame.isEmpty)
        #expect(configuration.reminderDestinationListIDsByFrame.isEmpty)
        #expect(configuration.photoDestinationIntentIDsByFrame.isEmpty)
        #expect(configuration.reminderDestinationIntentIDsByFrame.isEmpty)
    }

    @Test("Older sync state decodes without frame destination records")
    func photoDestinationStateIsBackwardCompatible() throws {
        let state = try JSONDecoder().decode(SyncState.self, from: Data("{}".utf8))

        #expect(state.photoDestinations.isEmpty)
        #expect(state.pendingPhotoCleanups.isEmpty)
    }

    @Test("Changing frames clears only frame-scoped destination identifiers")
    @MainActor
    func changingFramesClearsDestinationIdentifiers() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.account.deviceID = "device-1"
        var photo = PhotoMapping()
        photo.destinationAlbumID = "album-1"
        configuration.photoMappings = [photo]
        var reminder = ReminderListMapping()
        reminder.destinationListID = "list-1"
        configuration.reminderMappings = [reminder]
        configuration.recipeSelection.destinationCategoryID = "category-1"
        configuration.mealSelection.destinationCategoryID = "category-2"
        let persistence = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x41, count: 32)
            ),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x42, count: 32)
            )
        )
        try persistence.saveConfiguration(configuration)
        let store = AppStore(persistence: persistence)

        store.prepareForFrameChange(from: "frame-1", to: "frame-2")

        #expect(store.configuration.account.frameID == "frame-2")
        #expect(store.configuration.account.deviceID.isEmpty)
        #expect(store.configuration.photoMappings.first?.destinationAlbumID == nil)
        #expect(store.configuration.reminderMappings.first?.destinationListID.isEmpty == true)
        #expect(store.configuration.recipeSelection.destinationCategoryID == nil)
        #expect(store.configuration.mealSelection.destinationCategoryID == nil)
        #expect(store.configuration.recipeDestinationCategoryIDsByFrame["frame-1"] == "category-1")
        #expect(store.configuration.mealDestinationCategoryIDsByFrame["frame-1"] == "category-2")

        store.configuration.recipeSelection.destinationCategoryID = "category-frame-2"
        store.configuration.mealSelection.destinationCategoryID = "meal-frame-2"
        store.prepareForFrameChange(from: "frame-2", to: "frame-1")

        #expect(store.configuration.recipeSelection.destinationCategoryID == "category-1")
        #expect(store.configuration.mealSelection.destinationCategoryID == "category-2")
        #expect(store.configuration.photoMappings.first?.destinationAlbumID == "album-1")
        #expect(store.configuration.reminderMappings.first?.destinationListID == "list-1")
        #expect(
            store.configuration.recipeDestinationCategoryIDsByFrame["frame-2"]
                == "category-frame-2"
        )
        #expect(
            store.configuration.mealDestinationCategoryIDsByFrame["frame-2"]
                == "meal-frame-2"
        )
    }

    @Test("Configured frame destinations survive newer choices than sync state")
    @MainActor
    func configuredFrameDestinationsOverrideOldState() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testConfigurationStore(rootURL: directory)
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        try persistence.saveConfiguration(configuration)
        let store = AppStore(persistence: persistence)
        let photo = PhotoMapping(
            name: "Family",
            destinationAlbumID: "album-new",
            destinationAlbumTitle: "New Album"
        )
        let photoID = photo.id
        let reminder = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListID: "list-new",
            destinationListTitle: "New List",
            destinationKind: .toDo,
            direction: .appleToSkylight,
            enabled: false
        )
        let reminderID = reminder.id
        store.savePhotoMapping(
            photo,
            destinationSelectionChanged: true,
            triggerSync: false
        )
        store.saveReminderMapping(
            reminder,
            destinationSelectionChanged: true,
            triggerSync: false
        )
        let photoIntentID = try #require(
            store.configuration.photoDestinationIntentIDsByFrame[
                FrameDestinationIdentity.key(mappingID: photoID, frameID: "frame-1")
            ]
        )
        let reminderIntentID = try #require(
            store.configuration.reminderDestinationIntentIDsByFrame[
                FrameDestinationIdentity.key(mappingID: reminderID, frameID: "frame-1")
            ]
        )
        store.prepareForFrameChange(from: "frame-1", to: "frame-2")
        store.prepareForFrameChange(from: "frame-2", to: "frame-1")
        store.skylightAlbums = [
            album(id: "album-old", title: "Old Album"),
            album(id: "album-new", title: "New Album")
        ]
        store.skylightLists = [
            list(id: "list-old", title: "Old List"),
            list(id: "list-new", title: "New List")
        ]
        var state = SyncState()
        state.photoDestinations = [PhotoDestinationSyncRecord(
            mappingID: photoID,
            frameID: "frame-1",
            albumID: "album-old",
            destinationIntentID: UUID()
        )]
        state.reminderLists = [ReminderListSyncRecord(
            mappingID: reminderID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "list-old",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Old List",
            destinationIntentID: UUID()
        )]

        store.hydrateUniqueDestinationIDs(from: state)

        #expect(store.configuration.photoMappings.first?.destinationAlbumID == "album-new")
        #expect(store.configuration.reminderMappings.first?.destinationListID == "list-new")
        #expect(
            store.configuration.photoDestinationIntentIDsByFrame[
                FrameDestinationIdentity.key(mappingID: photoID, frameID: "frame-1")
            ] == photoIntentID
        )
        #expect(
            store.configuration.reminderDestinationIntentIDsByFrame[
                FrameDestinationIdentity.key(mappingID: reminderID, frameID: "frame-1")
            ] == reminderIntentID
        )
    }

    @Test("Explicit new destinations do not hydrate from same-title old records")
    @MainActor
    func explicitNewDestinationSkipsTitleHydration() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = PhotoMapping(
            name: "Family",
            destinationAlbumTitle: "Family"
        )
        let reminder = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListTitle: "Groceries",
            destinationKind: .toDo,
            direction: .appleToSkylight,
            enabled: true
        )
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.photoMappings = [photo]
        configuration.reminderMappings = [reminder]
        configuration.photoDestinationIntentIDsByFrame[
            FrameDestinationIdentity.key(mappingID: photo.id, frameID: "frame-1")
        ] = UUID()
        configuration.reminderDestinationIntentIDsByFrame[
            FrameDestinationIdentity.key(mappingID: reminder.id, frameID: "frame-1")
        ] = UUID()
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let store = AppStore(persistence: persistence)
        store.skylightAlbums = [album(id: "album-old", title: "Family")]
        store.skylightLists = [list(id: "list-old", title: "Groceries")]
        var state = SyncState()
        state.photoDestinations = [PhotoDestinationSyncRecord(
            mappingID: photo.id,
            frameID: "frame-1",
            albumID: "album-old",
            destinationIntentID: UUID()
        )]
        state.reminderLists = [ReminderListSyncRecord(
            mappingID: reminder.id,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "list-old",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Groceries",
            destinationIntentID: UUID()
        )]

        store.hydrateUniqueDestinationIDs(from: state)

        #expect(store.configuration.photoMappings.first?.destinationAlbumID == nil)
        #expect(store.configuration.reminderMappings.first?.destinationListID == "")
    }

    @Test("Pending shared photo retirement survives relaunch until completion")
    @MainActor
    func pendingPhotoRetirementIsDurable() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testConfigurationStore(rootURL: directory)
        let mapping = PhotoMapping(name: "Family", sourceKind: .selectedPhotos)
        var configuration = AppConfiguration.empty
        configuration.pendingPhotoMappingRetirements = [mapping]
        configuration.retiredPhotoMappingIDs = [mapping.id]
        try persistence.saveConfiguration(configuration)

        let reloaded = AppStore(persistence: persistence)
        #expect(reloaded.configuration.pendingPhotoMappingRetirements.map(\.id) == [mapping.id])

        reloaded.acknowledgePhotoMappingRetirement(
            mapping.id,
            savedRecordIsEnabled: true
        )
        #expect(reloaded.configuration.pendingPhotoMappingRetirements.map(\.id) == [mapping.id])

        reloaded.acknowledgePhotoMappingRetirement(
            mapping.id,
            savedRecordIsEnabled: false
        )

        let persisted = try persistence.loadConfiguration()
        #expect(persisted.pendingPhotoMappingRetirements.isEmpty)
        #expect(persisted.retiredPhotoMappingIDs == [mapping.id])
    }

    @Test("Shared photo mappings never carry a frame-scoped album ID")
    func sharedPhotoMappingKeepsDestinationIDsLocal() throws {
        var local = PhotoMapping(
            name: "Family",
            sourceKind: .selectedPhotos,
            destinationAlbumID: "album-frame-a",
            destinationAlbumTitle: "Family"
        )
        let shared = SharedPhotoMapping.portable(
            from: local,
            modifiedByInstallationID: "mac-a"
        )

        #expect(shared.destinationAlbumID == nil)
        #expect(shared.localPhotoMapping().destinationAlbumID == nil)

        let unsafeRemote = SharedPhotoMapping(
            id: local.id,
            name: "Updated Family",
            destinationAlbumID: "album-frame-b",
            destinationAlbumTitle: "Renamed Family",
            removalPolicy: .keepOnSkylight,
            maximumLongEdge: local.maximumLongEdge,
            jpegQuality: local.jpegQuality,
            isEnabled: local.enabled,
            modifiedByInstallationID: "mac-b"
        )
        unsafeRemote.applyPortableFields(to: &local)

        #expect(local.destinationAlbumID == "album-frame-a")
        #expect(local.destinationAlbumTitle == "Renamed Family")
        #expect(!unsafeRemote.matchesPortableFields(of: local))

        let retired = SharedPhotoMapping.portableRetirement(
            from: local,
            at: Date(timeIntervalSince1970: 500),
            modifiedByInstallationID: "mac-a"
        )
        #expect(!retired.isEnabled)
        #expect(retired.destinationAlbumID == nil)
        #expect(retired.modifiedAt == Date(timeIntervalSince1970: 500))
    }

    @Test("Destination hydration prefers exact frame state over a matching old title")
    @MainActor
    func destinationHydrationUsesExactFrameState() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoMappingID = UUID()
        let reminderMappingID = UUID()
        var photo = PhotoMapping(
            name: "Family",
            destinationAlbumTitle: "Original Album"
        )
        photo.id = photoMappingID
        var reminder = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListTitle: "Original List",
            destinationKind: .toDo,
            direction: .appleToSkylight,
            enabled: true
        )
        reminder.id = reminderMappingID
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.photoMappings = [photo]
        configuration.reminderMappings = [reminder]
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let store = AppStore(persistence: persistence)
        store.skylightAlbums = [
            album(id: "album-exact", title: "Renamed Album"),
            album(id: "album-title-match", title: "Original Album")
        ]
        store.skylightLists = [
            list(id: "list-exact", title: "Renamed List"),
            list(id: "list-title-match", title: "Original List")
        ]
        var state = SyncState()
        state.photoAlbums = [PhotoAlbumRecord(
            mappingID: photoMappingID,
            frameID: "frame-1",
            albumID: "album-title-match"
        )]
        state.photoDestinations = [PhotoDestinationSyncRecord(
            mappingID: photoMappingID,
            frameID: "frame-1",
            albumID: "album-exact"
        )]
        state.reminderLists = [ReminderListSyncRecord(
            mappingID: reminderMappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "list-exact",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Renamed List"
        )]

        store.hydrateUniqueDestinationIDs(from: state)

        #expect(store.configuration.photoMappings.first?.destinationAlbumID == "album-exact")
        #expect(store.configuration.reminderMappings.first?.destinationListID == "list-exact")
    }

    @Test("Removing a reminder mapping locally clears only its identity records")
    func localReminderMappingRemovalDoesNotNeedRemoteAccess() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let removedID = UUID()
        let retainedID = UUID()
        var state = SyncState()
        state.reminders = [
            reminderRecord(mappingID: removedID, frameID: "frame-1"),
            reminderRecord(mappingID: retainedID, frameID: "frame-1")
        ]
        state.reminderLists = [
            reminderListRecord(mappingID: removedID),
            reminderListRecord(mappingID: retainedID)
        ]
        let store = SyncStateStore(
            rootURL: directory,
            authenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x43, count: 32))
        )
        try await store.save(state)

        try await store.removeReminderMappingRecords(mappingID: removedID)

        let loaded = try await store.load()
        #expect(loaded.reminders.map(\.mappingID) == [retainedID])
        #expect(loaded.reminderLists.map(\.mappingID) == [retainedID])
    }

    @Test("A transient first connection failure does not suppress later restore attempts")
    @MainActor
    func savedCredentialsClearSignedOutIntentBeforeConnecting() async throws {
        let signedOutKey = "isSkylightSignedOut"
        UserDefaults.standard.set(true, forKey: signedOutKey)
        defer { UserDefaults.standard.removeObject(forKey: signedOutKey) }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x44, count: 32)
            ),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x45, count: 32)
            )
        )
        let sessions = FailingAppSessionManager()
        let store = AppStore(persistence: persistence, sessionManager: sessions)

        await store.saveAccountCredentials(email: "person@example.com", password: "secret")

        #expect(!UserDefaults.standard.bool(forKey: signedOutKey))
        #expect(await sessions.connectAttempts == 1)

        await store.restoreAccountConnection()

        #expect(await sessions.clientAttempts == 1)
    }

    @Test("Reconnect records an automatically selected replacement frame")
    @MainActor
    func reconnectRecordsReplacementFramePreference() async throws {
        let signedOutKey = "isSkylightSignedOut"
        UserDefaults.standard.removeObject(forKey: signedOutKey)
        defer { UserDefaults.standard.removeObject(forKey: signedOutKey) }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-missing"
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let client = SkylightAPIClient(
            accessToken: "token",
            transport: FrameHydrationTransport()
        )
        let stateStore = SyncStateStore(
            rootURL: stateDirectory,
            authenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x75, count: 32))
        )
        let store = AppStore(
            persistence: persistence,
            sessionManager: StaticClientSessionManager(client: client),
            syncStateStore: stateStore
        )

        await store.restoreAccountConnection()

        #expect(store.configuration.account.frameID == "frame-2")
        #expect(store.configuration.account.deviceID == "device-2")
        #expect(store.sharedPreferenceMutations.selectedFrame?.value == "frame-2")
        #expect(store.sharedPreferenceMutationVersion == 1)
        #expect(try persistence.loadConfiguration() == store.configuration)
    }

    @Test("Sign-in records a replacement frame before destination refresh fails")
    @MainActor
    func signInRecordsReplacementFrameBeforeRefreshFailure() async throws {
        let signedOutKey = "isSkylightSignedOut"
        UserDefaults.standard.removeObject(forKey: signedOutKey)
        defer { UserDefaults.standard.removeObject(forKey: signedOutKey) }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-missing"
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let store = AppStore(
            persistence: persistence,
            sessionManager: ReplacementFrameSessionManager()
        )

        await store.saveAccountCredentials(email: "person@example.com", password: "secret")

        #expect(store.configuration.account.frameID == "frame-2")
        #expect(store.sharedPreferenceMutations.selectedFrame?.value == "frame-2")
        #expect(store.sharedPreferenceMutationVersion == 1)
        #expect(try persistence.loadConfiguration().account.frameID == "frame-2")
        #expect(store.connectionError != nil)
    }

    @Test("Sign-out blocks reconnect and sync until Keychain cleanup finishes")
    @MainActor
    func signOutOwnsTheConnectionLifecycle() async throws {
        let signedOutKey = "isSkylightSignedOut"
        UserDefaults.standard.removeObject(forKey: signedOutKey)
        defer { UserDefaults.standard.removeObject(forKey: signedOutKey) }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        let mapping = PhotoMapping(name: "Family")
        configuration.photoMappings = [mapping]
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let sessions = SuspendingSignOutSessionManager()
        let store = AppStore(persistence: persistence, sessionManager: sessions)
        store.skylightFrames = [SkylightResource(
            id: "frame-1",
            attributes: SkylightFrameAttributes(
                name: "Kitchen",
                timezone: "America/New_York",
                plus: false
            )
        )]

        let signOut = Task { await store.signOut() }
        await sessions.waitUntilSignOutStarts()

        #expect(store.isConnecting)
        #expect(store.skylightFrames.isEmpty)
        #expect(!store.isSkylightConnected)
        await store.saveAccountCredentials(email: "person@example.com", password: "secret")
        await store.syncNow()
        await store.refreshSkylightDestinations()
        await store.selectFrame("frame-2", replacing: "frame-1")
        await store.removePhotoMapping(mapping)
        #expect(await sessions.savedCredentialCount == 0)
        #expect(await sessions.clientAttempts == 0)
        #expect(store.configuration.account.frameID == "frame-1")
        #expect(store.configuration.photoMappings.map(\.id) == [mapping.id])

        await sessions.finishSignOut()
        await signOut.value

        #expect(!store.isConnecting)
        #expect(UserDefaults.standard.bool(forKey: signedOutKey))
    }

    @Test("An active session operation prevents sign-out from revoking its tokens")
    @MainActor
    func activeSessionOperationExcludesSignOut() async throws {
        let signedOutKey = "isSkylightSignedOut"
        UserDefaults.standard.removeObject(forKey: signedOutKey)
        defer { UserDefaults.standard.removeObject(forKey: signedOutKey) }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(.empty)
        let sessions = SuspendingClientSessionManager()
        let store = AppStore(persistence: persistence, sessionManager: sessions)

        let refresh = Task { await store.refreshSkylightDestinations() }
        await sessions.waitUntilClientStarts()
        await store.signOut()

        #expect(store.isConnecting)
        #expect(await sessions.signOutAttempts == 0)
        #expect(!UserDefaults.standard.bool(forKey: signedOutKey))

        await sessions.finishClient()
        await refresh.value
        #expect(!store.isConnecting)
    }

    @Test("A configuration load failure protects the original file and skips startup connection")
    @MainActor
    func configurationLoadFailureIsReadOnly() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalStore = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x51, count: 32)
            ),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x52, count: 32)
            )
        )
        var original = AppConfiguration.empty
        original.account.frameID = "frame-1"
        original.photoMappings = [PhotoMapping(name: "Family")]
        try originalStore.saveConfiguration(original)
        let configurationURL = directory.appendingPathComponent("configuration.json")
        let originalBytes = try Data(contentsOf: configurationURL)
        let unreadableStore = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x53, count: 32)
            ),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x52, count: 32)
            )
        )
        let sessions = FailingAppSessionManager()
        let store = AppStore(persistence: unreadableStore, sessionManager: sessions)

        #expect(store.configurationLoadError != nil)
        await store.start()
        #expect(store.statusMessage.contains("Configuration recovery is required"))
        store.configuration.dryRun = false
        #expect(!store.saveConfiguration())
        await store.restoreAccountConnection()
        await store.refreshSharediCloudState()

        #expect(try Data(contentsOf: configurationURL) == originalBytes)
        #expect(try originalStore.loadConfiguration() == original)
        #expect(await sessions.connectAttempts == 0)
        #expect(await sessions.clientAttempts == 0)
        #expect(!store.hasLoadedSharediCloudState)
        #expect(store.recoveryStatusMessage?.contains("Configuration recovery is required") == true)
    }

    @Test("An activity load failure protects the original history")
    @MainActor
    func activityLoadFailureIsReadOnly() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationKey = Data(repeating: 0x61, count: 32)
        let activityKey = Data(repeating: 0x62, count: 32)
        let originalStore = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(testKey: activityKey)
        )
        let baseline = [ActivityEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            date: Date(timeIntervalSince1970: 100),
            level: .info,
            area: .system,
            message: "Existing activity"
        )]
        try originalStore.saveActivity(baseline)
        let activityURL = directory.appendingPathComponent("activity.json")
        let originalBytes = try Data(contentsOf: activityURL)
        let unreadableStore = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x63, count: 32)
            )
        )
        let store = AppStore(persistence: unreadableStore)

        #expect(store.activityLoadError != nil)
        store.appendActivity(.init(level: .error, area: .system, message: "New entry"))
        store.clearActivity()
        store.completeSourceRefresh()

        #expect(store.activity.isEmpty)
        #expect(store.statusMessage.contains("Activity recovery is required"))
        #expect(try Data(contentsOf: activityURL) == originalBytes)
        #expect(try originalStore.loadActivity() == baseline)
    }

    @Test("Failed chore setup removes only the lists it just created")
    @MainActor
    func failedChoreSetupRollsBackCreatedLists() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationKey = Data(repeating: 0x64, count: 32)
        let activityKey = Data(repeating: 0x65, count: 32)
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        let normalPersistence = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(testKey: activityKey)
        )
        try normalPersistence.saveConfiguration(configuration)
        let failingPersistence = ConfigurationStore(
            fileManager: FailAfterCreateDirectoryFileManager(successfulCalls: 0),
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(testKey: activityKey)
        )
        let transport = ChoreSetupTransport()
        let client = SkylightAPIClient(accessToken: "token", transport: transport)
        let sessions = StaticClientSessionManager(client: client)
        let reminders = ChoreSetupRemindersStore()
        let store = AppStore(
            persistence: failingPersistence,
            sessionManager: sessions,
            remindersStore: reminders
        )
        store.skylightFrames = [SkylightResource(
            id: "frame-1",
            attributes: SkylightFrameAttributes(
                name: "Kitchen",
                timezone: "America/New_York",
                plus: false
            )
        )]

        await store.setupChoreListsFromSkylight()

        #expect(store.configuration.choreMappings.isEmpty)
        #expect(reminders.createdTitles == ["Oliver Chores", "Up for Grabs"])
        #expect(Set(reminders.deletedListIDs) == ["created-list-1", "created-list-2"])
        #expect(try reminders.lists().isEmpty)
        #expect(try normalPersistence.loadConfiguration().choreMappings.isEmpty)
        #expect(store.statusMessage.contains("could not be saved"))
    }

    @Test("A shared frame change waits for sync and hydrates the selected frame")
    @MainActor
    func sharedFrameChangeIsSerializedAndHydrated() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let client = SkylightAPIClient(
            accessToken: "token",
            transport: FrameHydrationTransport()
        )
        let store = AppStore(
            persistence: persistence,
            sessionManager: StaticClientSessionManager(client: client),
            remindersStore: ChoreSetupRemindersStore()
        )
        store.skylightFrames = [
            SkylightResource(
                id: "frame-1",
                attributes: SkylightFrameAttributes(name: "Office", timezone: "UTC", plus: false)
            ),
            SkylightResource(
                id: "frame-2",
                attributes: SkylightFrameAttributes(
                    name: "Kitchen",
                    timezone: "America/New_York",
                    plus: false
                )
            )
        ]
        store.isSyncing = true
        let preferences = SharedPreferences(
            selectedFrameID: "frame-2",
            dryRun: false,
            preferredSyncIntervalMinutes: 30,
            modifiedAt: Date(timeIntervalSince1970: 500),
            modifiedByInstallationID: "phone"
        )
        let apply = Task { try await store.applySharedPreferences(preferences) }
        await Task.yield()

        #expect(store.configuration.account.frameID == "frame-1")
        store.isSyncing = false
        try await apply.value

        #expect(store.configuration.account.frameID == "frame-2")
        #expect(store.configuration.account.deviceID == "device-2")
        #expect(store.configuration.dryRun == false)
        #expect(store.configuration.syncIntervalMinutes == 30)
        #expect(store.skylightAlbums.map(\.id) == ["album-2"])
        #expect(store.skylightLists.map(\.id) == ["list-2"])
        #expect(try persistence.loadConfiguration() == store.configuration)
    }

    @Test("Foreground shared settings survive an in-flight iCloud refresh")
    @MainActor
    func sharedPreferenceRefreshPreservesForegroundChanges() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaults = UserDefaults.standard
        let preferencesKey = "shared-preferences-v1"
        let installationKey = "cloud-installation-id"
        let previousPreferences = defaults.data(forKey: preferencesKey)
        let previousInstallationID = defaults.string(forKey: installationKey)
        defer {
            if let previousPreferences {
                defaults.set(previousPreferences, forKey: preferencesKey)
            } else {
                defaults.removeObject(forKey: preferencesKey)
            }
            if let previousInstallationID {
                defaults.set(previousInstallationID, forKey: installationKey)
            } else {
                defaults.removeObject(forKey: installationKey)
            }
        }

        let cached = SharedPreferences(
            selectedFrameID: "frame-1",
            dryRun: true,
            preferredSyncIntervalMinutes: 15,
            modifiedAt: Date(timeIntervalSince1970: 100),
            modifiedByInstallationID: "mac"
        )
        defaults.set(try JSONEncoder().encode(cached), forKey: preferencesKey)
        defaults.set("mac", forKey: installationKey)

        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.dryRun = true
        configuration.syncIntervalMinutes = 15
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let remote = SharedPreferences(
            selectedFrameID: "frame-1",
            dryRun: true,
            preferredSyncIntervalMinutes: 15,
            modifiedAt: Date(timeIntervalSince1970: 200),
            modifiedByInstallationID: "phone"
        )
        let cloudStore = SuspendedPreferencesStore(remote: remote)
        let client = SkylightAPIClient(
            accessToken: "token",
            transport: FrameHydrationTransport()
        )
        let stateStore = SyncStateStore(
            rootURL: directory.appendingPathComponent("sync-state", isDirectory: true),
            authenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x74, count: 32))
        )
        let store = AppStore(
            persistence: persistence,
            sessionManager: StaticClientSessionManager(client: client),
            syncStateStore: stateStore,
            sharedPreferencesStore: cloudStore
        )
        store.skylightFrames = [
            SkylightResource(
                id: "frame-1",
                attributes: SkylightFrameAttributes(name: "Office", timezone: "UTC", plus: false)
            ),
            SkylightResource(
                id: "frame-2",
                attributes: SkylightFrameAttributes(
                    name: "Kitchen",
                    timezone: "America/New_York",
                    plus: false
                )
            )
        ]

        let refresh = Task {
            try await store.refreshSharedPreferences(using: cloudStore)
        }
        await cloudStore.waitUntilLoadStarts()

        #expect(await store.selectFrame("frame-2", replacing: "frame-1"))
        store.configuration.dryRun = false
        store.configuration.syncIntervalMinutes = 45
        #expect(store.saveConfiguration(
            sharedPreferenceFields: [.dryRun, .syncInterval],
            publishSharedState: false
        ))
        await cloudStore.resumeLoad()
        let resolved = try await refresh.value
        let saved = try #require(await cloudStore.savedPreferences())
        let savedConfiguration = try persistence.loadConfiguration()

        #expect(store.configuration.account.frameID == "frame-2")
        #expect(store.configuration.dryRun == false)
        #expect(store.configuration.syncIntervalMinutes == 45)
        #expect(resolved.selectedFrameID == "frame-2")
        #expect(resolved.dryRun == false)
        #expect(resolved.preferredSyncIntervalMinutes == 45)
        #expect(saved.selectedFrameID == "frame-2")
        #expect(saved.dryRun == false)
        #expect(saved.preferredSyncIntervalMinutes == 45)
        #expect(savedConfiguration == store.configuration)
    }

    @Test("Explicit sign-in is blocked while sync owns the account snapshot")
    @MainActor
    func explicitSignInDoesNotOverlapSync() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(.empty)
        let sessions = FailingAppSessionManager()
        let store = AppStore(persistence: persistence, sessionManager: sessions)
        store.isSyncing = true

        await store.saveAccountCredentials(email: "person@example.com", password: "secret")

        #expect(await sessions.savedCredentialCount == 0)
        #expect(!store.isConnecting)
    }

    @Test("A failed frame switch restores configuration and destination resources")
    @MainActor
    func failedFrameSwitchRollsBack() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.account.deviceID = "device-1"
        let photo = PhotoMapping(name: "Family", destinationAlbumID: "album-1")
        configuration.photoMappings = [photo]
        configuration.photoDestinationAlbumIDsByFrame[
            FrameDestinationIdentity.key(mappingID: photo.id, frameID: "frame-1")
        ] = "album-1"
        let persistence = testConfigurationStore(rootURL: directory)
        try persistence.saveConfiguration(configuration)
        let sessions = FailingAppSessionManager()
        let store = AppStore(persistence: persistence, sessionManager: sessions)
        let device = try JSONDecoder().decode(
            SkylightResource<SkylightDeviceAttributes>.self,
            from: Data(#"{"id":"device-1","attributes":{"name":"Kitchen"}}"#.utf8)
        )
        store.skylightDevices = [device]
        store.skylightAlbums = [album(id: "album-1", title: "Family")]
        store.skylightLists = [list(id: "list-1", title: "Groceries")]
        store.skylightMealCategories = [SkylightResource(
            id: "meal-category-1",
            attributes: SkylightMealCategoryAttributes(label: "Dinner", color: nil)
        )]
        store.skylightChoreCategories = [SkylightResource(
            id: "chore-category-1",
            attributes: SkylightCategoryAttributes(
                label: "Oliver",
                color: nil,
                linkedToProfile: nil,
                selectedForChoreChart: true
            )
        )]
        let priorConfiguration = store.configuration
        let priorDevices = store.skylightDevices
        let priorAlbums = store.skylightAlbums
        let priorLists = store.skylightLists
        let priorMealCategories = store.skylightMealCategories
        let priorChoreCategories = store.skylightChoreCategories

        await store.selectFrame("frame-2", replacing: "frame-1")

        #expect(store.configuration == priorConfiguration)
        #expect(store.skylightDevices == priorDevices)
        #expect(store.skylightAlbums == priorAlbums)
        #expect(store.skylightLists == priorLists)
        #expect(store.skylightMealCategories == priorMealCategories)
        #expect(store.skylightChoreCategories == priorChoreCategories)
        #expect(await sessions.clientAttempts == 1)
        #expect(try persistence.loadConfiguration() == priorConfiguration)
    }

    @Test("A frame switch persists its hydrated state in one transaction")
    @MainActor
    func frameSwitchUsesOneConfigurationWrite() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        let configurationKey = Data(repeating: 0x71, count: 32)
        let activityKey = Data(repeating: 0x72, count: 32)
        var configuration = AppConfiguration.empty
        configuration.account.frameID = "frame-1"
        configuration.account.deviceID = "device-1"
        configuration.photoMappings = [PhotoMapping(
            name: "Family",
            destinationAlbumID: "album-1",
            destinationAlbumTitle: "Family"
        )]
        let normalPersistence = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(testKey: activityKey)
        )
        try normalPersistence.saveConfiguration(configuration)
        let failingPersistence = ConfigurationStore(
            fileManager: FailAfterCreateDirectoryFileManager(successfulCalls: 1),
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(testKey: activityKey)
        )
        let stateStore = SyncStateStore(
            rootURL: stateDirectory,
            authenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x73, count: 32))
        )
        let client = SkylightAPIClient(
            accessToken: "token",
            transport: FrameHydrationTransport()
        )
        let store = AppStore(
            persistence: failingPersistence,
            sessionManager: StaticClientSessionManager(client: client),
            syncStateStore: stateStore
        )
        store.skylightFrames = [
            SkylightResource(
                id: "frame-1",
                attributes: SkylightFrameAttributes(name: "Office", timezone: "UTC", plus: false)
            ),
            SkylightResource(
                id: "frame-2",
                attributes: SkylightFrameAttributes(
                    name: "Kitchen",
                    timezone: "America/New_York",
                    plus: false
                )
            )
        ]

        let selected = await store.selectFrame("frame-2", replacing: "frame-1")
        let saved = try normalPersistence.loadConfiguration()

        #expect(selected)
        #expect(store.configuration.account.frameID == "frame-2")
        #expect(store.configuration.account.deviceID == "device-2")
        #expect(store.configuration.photoMappings.first?.destinationAlbumID == "album-2")
        #expect(store.skylightAlbums.map(\.id) == ["album-2"])
        #expect(saved == store.configuration)
    }

    @Test("A failed final mapping removal save leaves a disabled retry")
    @MainActor
    func mappingRemovalPersistsDisabledRetry() async throws {
        let configurationDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: configurationDirectory)
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        let mapping = ReminderListMapping(
            sourceListID: "apple-list",
            sourceListTitle: "Groceries",
            destinationListID: "skylight-list",
            destinationListTitle: "Groceries",
            destinationKind: .toDo,
            direction: .twoWay,
            enabled: true
        )
        var configuration = AppConfiguration.empty
        configuration.reminderMappings = [mapping]
        let configurationKey = Data(repeating: 0x54, count: 32)
        let activityKey = Data(repeating: 0x55, count: 32)
        let normalPersistence = ConfigurationStore(
            rootURL: configurationDirectory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(testKey: activityKey)
        )
        try normalPersistence.saveConfiguration(configuration)
        let stateStore = SyncStateStore(
            rootURL: stateDirectory,
            authenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x56, count: 32))
        )
        var state = SyncState()
        state.reminders = [reminderRecord(mappingID: mapping.id, frameID: "frame-1")]
        try await stateStore.save(state)
        let failingFileManager = FailAfterCreateDirectoryFileManager(successfulCalls: 1)
        let failingPersistence = ConfigurationStore(
            fileManager: failingFileManager,
            rootURL: configurationDirectory,
            configurationAuthenticator: LocalFileAuthenticator(testKey: configurationKey),
            activityAuthenticator: LocalFileAuthenticator(testKey: activityKey)
        )
        let store = AppStore(
            persistence: failingPersistence,
            syncStateStore: stateStore
        )

        await store.removeReminderMapping(mapping, cleanup: .none)

        #expect(store.configuration.reminderMappings.first?.enabled == false)
        #expect(try normalPersistence.loadConfiguration().reminderMappings.first?.enabled == false)
        #expect(try await stateStore.load().reminders.isEmpty)

        let reloaded = AppStore(
            persistence: normalPersistence,
            syncStateStore: stateStore
        )
        let disabled = try #require(reloaded.configuration.reminderMappings.first)
        await reloaded.removeReminderMapping(disabled, cleanup: .none)

        #expect(try normalPersistence.loadConfiguration().reminderMappings.isEmpty)
    }

    private func reminderRecord(mappingID: UUID, frameID: String) -> ReminderSyncRecord {
        ReminderSyncRecord(
            mappingID: mappingID,
            frameID: frameID,
            skylightListID: "list-1",
            appleReminderID: "apple-1",
            skylightItemID: "remote-1",
            lastAppleModifiedAt: .distantPast,
            lastSkylightModifiedAt: .distantPast,
            contentFingerprint: ""
        )
    }

    private func reminderListRecord(mappingID: UUID) -> ReminderListSyncRecord {
        ReminderListSyncRecord(
            mappingID: mappingID,
            frameID: "frame-1",
            appleListID: "apple-list",
            skylightListID: "skylight-list",
            lastSyncedAppleTitle: "Groceries",
            lastSyncedSkylightTitle: "Groceries"
        )
    }

    @MainActor
    private func testConfigurationStore(rootURL: URL) -> ConfigurationStore {
        ConfigurationStore(
            rootURL: rootURL,
            configurationAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x46, count: 32)
            ),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x47, count: 32)
            )
        )
    }

    private func album(
        id: String,
        title: String
    ) -> SkylightResource<SkylightAlbumAttributes> {
        SkylightResource(
            id: id,
            attributes: SkylightAlbumAttributes(
                title: title,
                messageCount: 0,
                createdAt: nil,
                updatedAt: nil
            )
        )
    }

    private func list(
        id: String,
        title: String
    ) -> SkylightResource<SkylightListAttributes> {
        SkylightResource(
            id: id,
            attributes: SkylightListAttributes(
                label: title,
                color: nil,
                kind: .toDo,
                hideOnDevice: false
            )
        )
    }
}

private struct ChoreSetupTransport: SkylightTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #expect(request.url?.path == "/api/frames/frame-1/categories")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let json = #"{"data":[{"id":"person-1","type":"category","attributes":{"label":"Oliver","selected_for_chore_chart":true}}]}"#
        return (Data(json.utf8), response)
    }
}

private struct FrameHydrationTransport: SkylightTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let json: String
        switch path {
        case "/api/frames":
            json = #"{"data":[{"id":"frame-2","type":"frame","attributes":{"name":"Kitchen","timezone":"America/New_York","plus":false}}]}"#
        case "/api/frames/frame-2/devices":
            json = #"{"data":[{"id":"device-2","type":"device","attributes":{"name":"Kitchen"}}]}"#
        case "/api/frames/frame-2/albums":
            json = #"{"data":[{"id":"album-2","type":"album","attributes":{"title":"Family"}}]}"#
        case "/api/frames/frame-2/lists":
            json = #"{"data":[{"id":"list-2","type":"list","attributes":{"label":"Groceries","kind":"shopping"}}]}"#
        case "/api/frames/frame-2/meals/categories":
            json = #"{"data":[{"id":"meal-2","type":"meal_category","attributes":{"label":"Dinner"}}]}"#
        case "/api/frames/frame-2/categories":
            json = #"{"data":[{"id":"person-2","type":"category","attributes":{"label":"Oliver","selected_for_chore_chart":true}}]}"#
        default:
            Issue.record("Unexpected frame hydration request: \(path)")
            throw AppSessionTestError.offline
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }
}

private struct FailingDestinationTransport: SkylightTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw AppSessionTestError.offline
    }
}

private actor StaticClientSessionManager: SkylightSessionManaging {
    let storedClient: SkylightAPIClient

    init(client: SkylightAPIClient) {
        storedClient = client
    }

    func storedEmail() async throws -> String? { "person@example.com" }
    func signOut() async throws {}
    func saveCredentials(email: String, password: String) async throws {}

    func connect(
        configuration: SkylightAccountConfiguration
    ) async throws -> SkylightAccountConnection {
        throw AppSessionTestError.offline
    }

    func client(
        configuration: SkylightAccountConfiguration,
        validateFrame: Bool
    ) async throws -> SkylightAPIClient {
        storedClient
    }
}

private actor ReplacementFrameSessionManager: SkylightSessionManaging {
    func storedEmail() async throws -> String? { "person@example.com" }
    func signOut() async throws {}
    func saveCredentials(email: String, password: String) async throws {}

    func connect(
        configuration: SkylightAccountConfiguration
    ) async throws -> SkylightAccountConnection {
        let frame = SkylightResource(
            id: "frame-2",
            attributes: SkylightFrameAttributes(
                name: "Kitchen",
                timezone: "America/New_York",
                plus: false
            )
        )
        return SkylightAccountConnection(
            client: SkylightAPIClient(
                accessToken: "token",
                transport: FailingDestinationTransport()
            ),
            frames: [frame],
            selectedFrameID: frame.id,
            devices: [],
            selectedDeviceID: ""
        )
    }

    func client(
        configuration: SkylightAccountConfiguration,
        validateFrame: Bool
    ) async throws -> SkylightAPIClient {
        throw AppSessionTestError.offline
    }
}

private actor SuspendedPreferencesStore: SharedPreferencesCloudStoring {
    private var remote: SharedPreferences?
    private var loadStarted = false
    private var loadContinuation: CheckedContinuation<SharedPreferences?, Never>?

    init(remote: SharedPreferences?) {
        self.remote = remote
    }

    func load() async throws -> SharedPreferences? {
        loadStarted = true
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func save(_ proposed: SharedPreferences) async throws -> SharedPreferences {
        let saved = remote?.merging(proposed) ?? proposed
        remote = saved
        return saved
    }

    func waitUntilLoadStarts() async {
        while !loadStarted {
            await Task.yield()
        }
    }

    func resumeLoad() {
        let continuation = loadContinuation
        loadContinuation = nil
        continuation?.resume(returning: remote)
    }

    func savedPreferences() -> SharedPreferences? {
        remote
    }
}

private actor CountingPreferencesStore: SharedPreferencesCloudStoring {
    private(set) var saveCount = 0

    func load() async throws -> SharedPreferences? { nil }

    func save(_ proposed: SharedPreferences) async throws -> SharedPreferences {
        saveCount += 1
        return proposed
    }
}

private actor RecordingPhotoMappingStore: SharedPhotoMappingCloudStoring {
    private var mappings: [SharedPhotoMapping] = []

    func loadMappings() async throws -> [SharedPhotoMapping] { mappings }

    func saveMapping(_ proposed: SharedPhotoMapping) async throws -> SharedPhotoMapping {
        mappings.append(proposed)
        return proposed
    }

    func loadSelections(for mappingID: UUID) async throws -> [SharedPhotoSelection] { [] }

    func saveSelection(_ proposed: SharedPhotoSelection) async throws -> SharedPhotoSelection {
        proposed
    }

    func savedMappings() -> [SharedPhotoMapping] { mappings }
}

@MainActor
private final class ChoreSetupRemindersStore: AppRemindersStoring {
    private(set) var currentLists: [AppleReminderListSnapshot] = []
    private(set) var createdTitles: [String] = []
    private(set) var deletedListIDs: [String] = []

    func authorizationStatus() -> AppleRemindersAuthorizationStatus { .fullAccess }
    func requestAccess() async throws -> Bool { true }
    func lists() throws -> [AppleReminderListSnapshot] { currentLists }
    func reminders(in listID: String) async throws -> [AppleReminderSnapshot] { [] }

    func createList(named title: String) throws -> AppleReminderListSnapshot {
        createdTitles.append(title)
        let list = AppleReminderListSnapshot(
            id: "created-list-\(createdTitles.count)",
            title: title,
            colorHex: nil,
            sourceID: "source-1",
            sourceTitle: "iCloud",
            allowsContentModifications: true
        )
        currentLists.append(list)
        return list
    }

    func deleteNewlyCreatedList(withID listID: String) throws {
        deletedListIDs.append(listID)
        currentLists.removeAll { $0.id == listID }
    }

    func syncRemoveReminder(withID reminderID: String) async throws {}
}

private actor FailingAppSessionManager: SkylightSessionManaging {
    private(set) var connectAttempts = 0
    private(set) var clientAttempts = 0
    private(set) var savedCredentialCount = 0

    func storedEmail() async throws -> String? { "person@example.com" }
    func signOut() async throws {}
    func saveCredentials(email: String, password: String) async throws {
        savedCredentialCount += 1
    }

    func connect(
        configuration: SkylightAccountConfiguration
    ) async throws -> SkylightAccountConnection {
        connectAttempts += 1
        throw AppSessionTestError.offline
    }

    func client(
        configuration: SkylightAccountConfiguration,
        validateFrame: Bool
    ) async throws -> SkylightAPIClient {
        clientAttempts += 1
        throw AppSessionTestError.offline
    }
}

private actor SuspendingSignOutSessionManager: SkylightSessionManaging {
    private var signOutContinuation: CheckedContinuation<Void, Never>?
    private(set) var signOutStarted = false
    private(set) var savedCredentialCount = 0
    private(set) var clientAttempts = 0

    func storedEmail() async throws -> String? { "person@example.com" }

    func signOut() async throws {
        signOutStarted = true
        await withCheckedContinuation { continuation in
            signOutContinuation = continuation
        }
    }

    func waitUntilSignOutStarts() async {
        while !signOutStarted {
            await Task.yield()
        }
    }

    func finishSignOut() {
        signOutContinuation?.resume()
        signOutContinuation = nil
    }

    func saveCredentials(email: String, password: String) async throws {
        savedCredentialCount += 1
    }

    func connect(
        configuration: SkylightAccountConfiguration
    ) async throws -> SkylightAccountConnection {
        throw AppSessionTestError.offline
    }

    func client(
        configuration: SkylightAccountConfiguration,
        validateFrame: Bool
    ) async throws -> SkylightAPIClient {
        clientAttempts += 1
        throw AppSessionTestError.offline
    }
}

private actor SuspendingClientSessionManager: SkylightSessionManaging {
    private var clientContinuation: CheckedContinuation<Void, Never>?
    private(set) var clientStarted = false
    private(set) var signOutAttempts = 0

    func storedEmail() async throws -> String? { nil }

    func signOut() async throws {
        signOutAttempts += 1
    }

    func saveCredentials(email: String, password: String) async throws {}

    func connect(
        configuration: SkylightAccountConfiguration
    ) async throws -> SkylightAccountConnection {
        throw AppSessionTestError.offline
    }

    func client(
        configuration: SkylightAccountConfiguration,
        validateFrame: Bool
    ) async throws -> SkylightAPIClient {
        clientStarted = true
        await withCheckedContinuation { continuation in
            clientContinuation = continuation
        }
        throw AppSessionTestError.offline
    }

    func waitUntilClientStarts() async {
        while !clientStarted {
            await Task.yield()
        }
    }

    func finishClient() {
        clientContinuation?.resume()
        clientContinuation = nil
    }
}

private enum AppSessionTestError: Error {
    case offline
}

private final class FailAfterCreateDirectoryFileManager: FileManager, @unchecked Sendable {
    private let successfulCalls: Int
    private var calls = 0

    init(successfulCalls: Int) {
        self.successfulCalls = successfulCalls
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        calls += 1
        guard calls <= successfulCalls else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}
