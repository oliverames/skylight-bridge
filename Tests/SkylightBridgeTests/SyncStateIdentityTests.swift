import Foundation
import SkylightBridgeShared
import Testing
@testable import SkylightBridge

@Suite(.serialized)
struct SyncStateIdentityTests {
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

private actor FailingAppSessionManager: SkylightSessionManaging {
    private(set) var connectAttempts = 0
    private(set) var clientAttempts = 0

    func storedEmail() async throws -> String? { "person@example.com" }
    func signOut() async throws {}
    func saveCredentials(email: String, password: String) async throws {}

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
