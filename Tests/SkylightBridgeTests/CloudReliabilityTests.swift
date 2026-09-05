import Foundation
import Testing
import SkylightBridgeShared
@testable import SkylightBridge

@Suite(.serialized) @MainActor
struct CloudReliabilityTests {
    private func fixture(photos: ReliabilityPhotos = ReliabilityPhotos(), preferences: ReliabilityPreferences = ReliabilityPreferences()) -> (AppStore, ConfigurationStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ConfigurationStore(rootURL: root,
            configurationAuthenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x46, count: 32)),
            activityAuthenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x47, count: 32)))
        let store = AppStore(persistence: persistence,
            syncStateStore: SyncStateStore(rootURL: root, authenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x48, count: 32))),
            sharedPreferencesStore: preferences, sharedPhotoMappingStore: photos,
            photoIdentifiers: IdentityPhotoIdentifiers())
        store.photosAuthorizationStatus = .fullAccess
        return (store, persistence)
    }

    @Test func oldPhotoAdditionLosesToNewerRemovalAndDrainsOutbox() async throws {
        let cloud = ReliabilityPhotos()
        let (store, persistence) = fixture(photos: cloud)
        let mapping = PhotoMapping(name: "Test", sourceKind: .selectedPhotos, selectedAssetIDs: ["photo"])
        store.configuration.photoMappings = [mapping]
        store.pendingSharedPhotoChanges.record(mappingID: mapping.id, additions: ["photo"], removals: [])
        let newer = SharedPhotoSelection.removing(mappingID: mapping.id, cloudAssetIdentifier: "photo", at: .now.addingTimeInterval(60), by: "remote")
        await cloud.setSelection(newer)
        try store.persistConfiguration()
        try await store.performSharediCloudRefresh()
        #expect(store.pendingSharedPhotoChanges.isEmpty)
        #expect(store.configuration.photoMappings.first?.selectedAssetIDs.isEmpty == true)
        #expect(try persistence.loadConfiguration().pendingSharedPhotoChanges.isEmpty)
    }

    @Test func incompleteInventoryPublishesHealthyExplicitAddition() async throws {
        let cloud = ReliabilityPhotos(incomplete: true)
        let (store, _) = fixture(photos: cloud)
        let mapping = PhotoMapping(name: "Test", sourceKind: .selectedPhotos, selectedAssetIDs: ["photo", "passive"])
        store.configuration.photoMappings = [mapping]
        store.pendingSharedPhotoChanges.record(mappingID: mapping.id, additions: ["photo"], removals: [])
        try store.persistConfiguration()
        await #expect(throws: CloudOperationErrors.self) { try await store.performSharediCloudRefresh() }
        #expect(store.pendingSharedPhotoChanges.isEmpty)
        #expect(await cloud.savedIdentifiers == ["photo"])
        #expect(store.configuration.photoMappings.first?.selectedAssetIDs.contains("passive") == true)
    }

    @Test func failedRetirementCannotClaimSuccessfulRefresh() async throws {
        let cloud = ReliabilityPhotos(failing: true)
        let (store, persistence) = fixture(photos: cloud)
        let mapping = PhotoMapping(name: "Removed", sourceKind: .selectedPhotos)
        store.configuration.retiredPhotoMappingIDs = [mapping.id]
        store.configuration.pendingPhotoMappingRetirements = [mapping]
        store.configuration.photoRetirementDates = [mapping.id: Date(timeIntervalSince1970: 100)]
        try store.persistConfiguration()
        #expect(await store.cloudSync.syncNow() == false)
        #expect(store.cloudSync.lastSuccessAt == nil)
        #expect(store.pendingCloudChangeCount > 0)
        #expect(try persistence.loadConfiguration().pendingPhotoMappingRetirements == [mapping])
        let count = await cloud.mappingSaves
        await store.retireSharedPhotoMapping(mapping)
        #expect(await cloud.mappingSaves == count)
    }

    @Test func oldRetirementResponsePreservesNewerRetirement() async throws {
        let cloud = ReliabilityPhotos(suspendRetirement: true)
        let (store, _) = fixture(photos: cloud)
        let mapping = PhotoMapping(name: "Removed", sourceKind: .selectedPhotos)
        let firstDate = Date(timeIntervalSince1970: 100)
        store.configuration.retiredPhotoMappingIDs = [mapping.id]
        store.configuration.pendingPhotoMappingRetirements = [mapping]
        store.configuration.photoRetirementDates = [mapping.id: firstDate]
        try store.persistConfiguration()
        let task = Task { await store.retireSharedPhotoMapping(mapping) }
        await cloud.waitForRetirement()
        store.configuration.photoRetirementDates?[mapping.id] = firstDate.addingTimeInterval(20)
        try store.persistConfiguration()
        await cloud.resumeRetirement()
        await task.value
        #expect(store.configuration.pendingPhotoMappingRetirements == [mapping])
        #expect(store.configuration.retiredPhotoMappingIDs.contains(mapping.id))
    }

    @Test func preferenceTimestampAndPendingStateSurviveRestart() throws {
        let (store, persistence) = fixture()
        store.configuration.syncIntervalMinutes = 120
        #expect(store.saveConfiguration(sharedPreferenceFields: [.syncInterval], publishSharedState: false))
        let saved = try persistence.loadConfiguration()
        #expect(saved.sharedPreferencesPending)
        #expect(saved.sharedPreferences?.preferredSyncIntervalMinutes == 120)
        #expect(saved.sharedPreferences?.preferredSyncIntervalModifiedAt == store.configuration.sharedPreferences?.preferredSyncIntervalModifiedAt)
    }

    @Test func mappingAcknowledgementCannotEraseLaterIdenticalEdit() {
        var pending = PendingSharedPhotoChanges()
        let mapping = PhotoMapping(name: "A", sourceKind: .selectedPhotos)
        pending.recordPortableMapping(mapping)
        let sent = pending
        var changed = mapping
        changed.name = "B"
        pending.recordPortableMapping(changed)
        pending.recordPortableMapping(mapping)
        pending.mappingDates?[mapping.id] = sent.mappingDates![mapping.id]!.addingTimeInterval(1)
        pending.acknowledge(sent)
        #expect(pending.portableMappings[mapping.id] == mapping)
    }
}

@MainActor private struct IdentityPhotoIdentifiers: SharedPhotoIdentifierProviding {
    func cloudAssetIdentifiers(for localIdentifiers: [String]) throws -> [String: String] { Dictionary(uniqueKeysWithValues: localIdentifiers.map { ($0, $0) }) }
    func localAssetIdentifiers(for cloudIdentifiers: [String]) throws -> [String: String] { Dictionary(uniqueKeysWithValues: cloudIdentifiers.map { ($0, $0) }) }
}
private actor ReliabilityPreferences: SharedPreferencesCloudStoring {
    func load() async throws -> SharedPreferences? { nil }
    func save(_ proposed: SharedPreferences) async throws -> SharedPreferences { proposed }
}
private actor ReliabilityPhotos: SharedPhotoMappingCloudStoring {
    let incomplete: Bool
    let failing: Bool
    var selection: SharedPhotoSelection?
    var savedIdentifiers: Set<String> = []
    var mappingSaves = 0
    let suspendRetirement: Bool
    var continuation: CheckedContinuation<Void, Never>?
    init(incomplete: Bool = false, failing: Bool = false, suspendRetirement: Bool = false) {
        self.incomplete = incomplete; self.failing = failing; self.suspendRetirement = suspendRetirement
    }
    func waitForRetirement() async { while continuation == nil { await Task.yield() } }
    func resumeRetirement() { continuation?.resume(); continuation = nil }
    func setSelection(_ value: SharedPhotoSelection) { selection = value }
    func loadMappings() async throws -> [SharedPhotoMapping] { [] }
    func loadSelections(for mappingID: UUID) async throws -> [SharedPhotoSelection] { selection.map { [$0] } ?? [] }
    func loadSelectionsResult(for mappingID: UUID) async throws -> CloudFetchResult<SharedPhotoSelection> {
        CloudFetchResult(values: selection.map { [$0] } ?? [], failures: incomplete ? [.init(recordName: "bad")] : [])
    }
    func saveMapping(_ proposed: SharedPhotoMapping) async throws -> SharedPhotoMapping {
        mappingSaves += 1
        if failing { throw URLError(.notConnectedToInternet) }
        if suspendRetirement {
            await withCheckedContinuation { continuation = $0 }
            var newer = proposed
            newer.isEnabled = true
            newer.modifiedAt = proposed.modifiedAt.addingTimeInterval(10)
            return newer
        }
        return proposed
    }
    func saveSelection(_ proposed: SharedPhotoSelection) async throws -> SharedPhotoSelection {
        savedIdentifiers.insert(proposed.cloudAssetIdentifier)
        return selection?.merging(proposed) ?? proposed
    }
}
