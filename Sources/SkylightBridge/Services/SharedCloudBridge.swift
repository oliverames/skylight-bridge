import Foundation
import SkylightBridgeShared

protocol SharedPreferencesCloudStoring: Sendable {
    func load() async throws -> SharedPreferences?
    func save(_ proposed: SharedPreferences) async throws -> SharedPreferences
}

extension CloudPreferencesStore: SharedPreferencesCloudStoring {}

enum SharedPreferencesApplicationError: Error, LocalizedError, Equatable {
    case frameSelectionFailed(String)
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case let .frameSelectionFailed(frameID):
            "The shared Skylight frame \(frameID) could not be selected and loaded."
        case .persistenceFailed:
            "The shared preferences could not be saved locally."
        }
    }
}

/// Connects the intentionally small CloudKit contract to macOS-only app
/// configuration. Apple Notes, credentials, device IDs, local sync links, and
/// activity never leave this Mac.
@MainActor
extension AppStore {
    func refreshSharediCloudState() async {
        guard configurationLoadError == nil else { return }

        do {
            try await waitForSharedPreferencesApplyWindow()
            hasLoadedSharediCloudState = false
            await retryPendingPhotoMappingRetirements()
            _ = try await refreshSharedPreferences(
                using: sharedPreferencesStore
            )
            let synchronizedPreferenceMutationVersion = sharedPreferenceMutationVersion

            if FeatureFlags.multiDeviceCoordinationEnabled {
                try await publishAndCheckHeartbeat()
            } else {
                multiClientWarning = nil
            }

            // Import explicit removes before publishing local selections. If a
            // phone removed a photo while this Mac was offline, publishing
            // first would create a newer add record and silently resurrect it.
            try await importSharedPhotoMappings()
            try await publishLocalSelectedPhotoMappings()
            // Keep full shared-state publishing suppressed until removes are
            // imported. A preference changed during the unrelated Cloud work
            // still gets one final serialized write before the flag flips.
            if sharedPreferenceMutationVersion != synchronizedPreferenceMutationVersion {
                _ = try await publishSharedPreferences(
                    using: sharedPreferencesStore
                )
            }
            recordSharediCloudSuccess()
            hasLoadedSharediCloudState = true
            statusMessage = "Shared preferences and selected photos are up to date with iCloud."
        } catch {
            recordSharediCloudFailure(error, savedLocally: false)
        }
    }

    func publishSharediCloudState(
        intentionalPhotoAdditions: [UUID: Set<String>] = [:]
    ) async {
        guard configurationLoadError == nil else { return }
        do {
            try await waitForSharedPreferencesApplyWindow()
            await retryPendingPhotoMappingRetirements()
            _ = try await publishSharedPreferences(
                using: sharedPreferencesStore
            )
            try await publishLocalSelectedPhotoMappings(
                intentionalPhotoAdditions: intentionalPhotoAdditions
            )
            recordSharediCloudSuccess()
       } catch {
           recordSharediCloudFailure(error, savedLocally: true)
       }
   }

    func importSharedSyncState() async {
        guard configurationLoadError == nil,
              FeatureFlags.multiDeviceCoordinationEnabled else { return }
        do {
            let stateStore = SyncStateStore()
            var state = try await stateStore.load()
            try await importSharedSyncStateInto(&state)
            try await stateStore.save(state)
        } catch {
            if !SharedCloudKitFailure.isProductionSchemaConfigurationError(error) {
                appendActivity(.init(
                    level: .warning,
                    area: .system,
                    message: "Could not import sync state from iCloud: \(error.localizedDescription)"
                ))
            }
        }
    }

    func publishSharedSyncState() async {
        guard configurationLoadError == nil,
              FeatureFlags.multiDeviceCoordinationEnabled else { return }
        do {
            let stateStore = SyncStateStore()
            let state = try await stateStore.load()
            try await publishSharedSyncStateFromState(state)
        } catch {
            if !SharedCloudKitFailure.isProductionSchemaConfigurationError(error) {
                appendActivity(.init(
                    level: .warning,
                    area: .system,
                    message: "Could not publish sync state to iCloud: \(error.localizedDescription)"
                ))
            }
        }
    }

    private func recordSharediCloudSuccess() {
        hasLoggedSharediCloudSchemaDeploymentFailure = false
    }

    private func publishAndCheckHeartbeat() async throws {
        let store = ClientHeartbeatStore()
        let heartbeat = ClientHeartbeat(
            installationID: cloudInstallationID,
            lastSeenAt: .now,
            frameID: configuration.account.frameID,
            isActivelySyncing: isSyncing
        )
        _ = try await store.publish(heartbeat)
        let others = try await store.otherActiveInstallations(
            excludingInstallationID: cloudInstallationID
        )
        if others.isEmpty {
            multiClientWarning = nil
        } else {
            let names = others.map { String($0.installationID.prefix(8)) }.joined(separator: ", ")
            multiClientWarning = "Another Mac (\(names)) is also syncing this Skylight frame. Running two Macs against the same frame can duplicate content."
        }
    }

    private func publishSharedSyncStateFromState(_ state: SyncState) async throws {
        let store = CloudSyncStateStore()
        let shared = SharedSyncState(
            photoLinks: state.photos.map {
                SharedPhotoLink(
                    mappingID: $0.mappingID.uuidString,
                    frameID: $0.frameID,
                    appleAssetID: $0.appleAssetID,
                    renderedHash: $0.renderedHash,
                    skylightMessageID: $0.skylightMessageID,
                    lastSyncedAt: $0.lastSyncedAt
                )
            },
            reminderLinks: state.reminders.map {
                SharedReminderLink(
                    mappingID: $0.mappingID.uuidString,
                    frameID: $0.frameID,
                    skylightListID: $0.skylightListID,
                    appleReminderID: $0.appleReminderID,
                    skylightItemID: $0.skylightItemID,
                    lastSyncedAt: $0.lastAppleModifiedAt
                )
            },
            recipeLinks: state.notes.filter { $0.kind == .recipes }.map {
                SharedRecipeLink(
                    frameID: $0.frameID,
                    appleNoteID: $0.appleNoteID,
                    skylightID: $0.skylightID,
                    lastSyncedAt: $0.lastSyncedAt
                )
            },
            modifiedByInstallationID: cloudInstallationID,
            modifiedAt: .now
        )
        _ = try await store.publish(shared)
    }

    private func importSharedSyncStateInto(_ state: inout SyncState) async throws {
        let store = CloudSyncStateStore()
        let local = SharedSyncState(
            photoLinks: state.photos.map {
                SharedPhotoLink(
                    mappingID: $0.mappingID.uuidString,
                    frameID: $0.frameID,
                    appleAssetID: $0.appleAssetID,
                    renderedHash: $0.renderedHash,
                    skylightMessageID: $0.skylightMessageID,
                    lastSyncedAt: $0.lastSyncedAt
                )
            },
            reminderLinks: state.reminders.map {
                SharedReminderLink(
                    mappingID: $0.mappingID.uuidString,
                    frameID: $0.frameID,
                    skylightListID: $0.skylightListID,
                    appleReminderID: $0.appleReminderID,
                    skylightItemID: $0.skylightItemID,
                    lastSyncedAt: $0.lastAppleModifiedAt
                )
            },
            recipeLinks: state.notes.filter { $0.kind == .recipes }.map {
                SharedRecipeLink(
                    frameID: $0.frameID,
                    appleNoteID: $0.appleNoteID,
                    skylightID: $0.skylightID,
                    lastSyncedAt: $0.lastSyncedAt
                )
            },
            modifiedByInstallationID: cloudInstallationID,
            modifiedAt: .distantPast
        )
        let merged = try await store.mergeRemote(into: local)
        let existingPhotoKeys = Set(state.photos.map {
            "\($0.frameID):\($0.mappingID.uuidString):\($0.appleAssetID)"
        })
        for link in merged.photoLinks
        where !existingPhotoKeys.contains("\(link.frameID):\(link.mappingID):\(link.appleAssetID)") {
            guard let mappingID = UUID(uuidString: link.mappingID) else { continue }
            state.photos.append(PhotoSyncRecord(
                mappingID: mappingID,
                frameID: link.frameID,
                appleAssetID: link.appleAssetID,
                renderedHash: link.renderedHash,
                skylightMessageID: link.skylightMessageID,
                skylightAlbumIDs: [],
                lastSyncedAt: link.lastSyncedAt
            ))
        }
        let existingReminderKeys = Set(state.reminders.map {
            "\($0.frameID):\($0.mappingID.uuidString):\($0.appleReminderID)"
        })
        for link in merged.reminderLinks
        where !existingReminderKeys.contains("\(link.frameID):\(link.mappingID):\(link.appleReminderID)") {
            guard let mappingID = UUID(uuidString: link.mappingID) else { continue }
            state.reminders.append(ReminderSyncRecord(
                mappingID: mappingID,
                frameID: link.frameID,
                skylightListID: link.skylightListID,
                appleReminderID: link.appleReminderID,
                skylightItemID: link.skylightItemID,
                lastAppleModifiedAt: link.lastSyncedAt,
                lastSkylightModifiedAt: link.lastSyncedAt,
                contentFingerprint: ""
            ))
        }
        // Keyed by frame and note, mirroring NoteSyncRecord.id, so links from
        // another device are not re-imported as duplicates for this frame.
        let existingRecipeKeys = Set(state.notes.filter { $0.kind == .recipes }.map {
            "\($0.frameID):\($0.appleNoteID)"
        })
        for link in merged.recipeLinks
        where !existingRecipeKeys.contains("\(link.frameID):\(link.appleNoteID)") {
            state.notes.append(NoteSyncRecord(
                kind: .recipes,
                frameID: link.frameID,
                appleNoteID: link.appleNoteID,
                contentHash: "",
                skylightID: link.skylightID,
                lastSyncedAt: link.lastSyncedAt
            ))
        }
    }

    private func recordSharediCloudFailure(_ error: any Error, savedLocally: Bool) {
        let requiresSchemaDeployment = SharedCloudKitFailure.isProductionSchemaConfigurationError(error)
        if requiresSchemaDeployment {
            guard !hasLoggedSharediCloudSchemaDeploymentFailure else { return }
            hasLoggedSharediCloudSchemaDeploymentFailure = true
            statusMessage = "iCloud sharing needs its schema deployed to production."
        }

        appendActivity(.init(
            level: .warning,
            area: .system,
            message: SharedCloudKitFailure.activityMessage(for: error, savedLocally: savedLocally)
        ))
    }

    /// Saves a photo mapping and mirrors only individual-photo changes to
    /// CloudKit. Album and Favorites mappings are intentionally device-local.
    @discardableResult
    func savePhotoMapping(
        _ mapping: PhotoMapping,
        destinationSelectionChanged: Bool = false,
        triggerSync: Bool = true
    ) -> Bool {
        let previousConfiguration = configuration
        let previous = configuration.photoMappings.first { $0.id == mapping.id }
        configuration.retiredPhotoMappingIDs.remove(mapping.id)
        configuration.pendingPhotoMappingRetirements.removeAll { $0.id == mapping.id }
        let frameID = configuration.account.frameID.trimmed
        if !frameID.isEmpty {
            let key = FrameDestinationIdentity.key(mappingID: mapping.id, frameID: frameID)
            if let destinationID = mapping.destinationAlbumID?.trimmed,
               !destinationID.isEmpty {
                configuration.photoDestinationAlbumIDsByFrame[key] = destinationID
            } else {
                configuration.photoDestinationAlbumIDsByFrame.removeValue(forKey: key)
            }
            if destinationSelectionChanged || previous == nil {
                configuration.photoDestinationIntentIDsByFrame[key] = UUID()
            }
        }
        if let index = configuration.photoMappings.firstIndex(where: { $0.id == mapping.id }) {
            configuration.photoMappings[index] = mapping
        } else {
            configuration.photoMappings.append(mapping)
        }
        guard saveConfiguration(triggerSync: triggerSync) else {
            configuration = previousConfiguration
            return false
        }

        guard mapping.sourceKind == .selectedPhotos else { return true }
        let addedAssetIDs = mapping.selectedAssetIDs.subtracting(previous?.selectedAssetIDs ?? [])
        let removedAssetIDs = (previous?.selectedAssetIDs ?? []).subtracting(mapping.selectedAssetIDs)
        Task {
            await publishSharediCloudState(
                intentionalPhotoAdditions: [mapping.id: addedAssetIDs]
            )
            await publishRemovedSelectedPhotos(removedAssetIDs, for: mapping)
        }
        return true
    }

    /// The shared package has no mapping-delete operation. Publish a newer
    /// disabled record so existing and newly connected devices stop syncing
    /// the retired mapping, while the local suppression set prevents reimport.
    func retireSharedPhotoMapping(_ mapping: PhotoMapping) async {
        guard mapping.sourceKind == .selectedPhotos else { return }
        do {
            let cloudMappings = CloudPhotoMappingStore()
            let retired = SharedPhotoMapping.portableRetirement(
                from: mapping,
                modifiedByInstallationID: cloudInstallationID
            )
            let saved = try await cloudMappings.saveMapping(retired)
            cacheSharedPhotoMapping(saved)
            acknowledgePhotoMappingRetirement(
                mapping.id,
                savedRecordIsEnabled: saved.isEnabled
            )
        } catch {
            if SharedCloudKitFailure.isProductionSchemaConfigurationError(error) {
                recordSharediCloudFailure(error, savedLocally: true)
                return
            }
            appendActivity(.init(
                level: .warning,
                area: .photos,
                message: "The mapping was removed on this Mac, but its disabled state could not be shared through iCloud: \(error.localizedDescription)"
            ))
        }
    }

    private func retryPendingPhotoMappingRetirements() async {
        for mapping in configuration.pendingPhotoMappingRetirements {
            await retireSharedPhotoMapping(mapping)
        }
    }

    func acknowledgePhotoMappingRetirement(
        _ mappingID: UUID,
        savedRecordIsEnabled: Bool
    ) {
        guard !savedRecordIsEnabled else {
            appendActivity(.init(
                level: .warning,
                area: .photos,
                message: "iCloud kept a newer active copy of the removed mapping. Its disabled state will be retried."
            ))
            return
        }
        completePhotoMappingRetirement(mappingID)
    }

    private func sharedPreferences() -> SharedPreferences {
        var preferences = loadSharedPreferences()
        let installationID = cloudInstallationID
        let now = Date.now

        if preferences.selectedFrameID != configuration.account.frameID {
            preferences.setSelectedFrameID(configuration.account.frameID, at: now, by: installationID)
        }
        if preferences.dryRun != configuration.dryRun {
            preferences.setDryRun(configuration.dryRun, at: now, by: installationID)
        }
        if preferences.preferredSyncIntervalMinutes != configuration.syncIntervalMinutes {
            preferences.setPreferredSyncInterval(configuration.syncIntervalMinutes, at: now, by: installationID)
        }
        return preferences
    }

    func refreshSharedPreferences(
        using cloudPreferences: any SharedPreferencesCloudStoring
    ) async throws -> SharedPreferences {
        try await acquireSharedPreferencesOperation()
        defer { sharedPreferencesOperationInProgress = false }

        let observedMutationVersion = sharedPreferenceMutationVersion
        let localPreferences = sharedPreferences()
        let resolvedPreferences: SharedPreferences
        if let remote = try await cloudPreferences.load() {
            let merged = localPreferences.merging(remote)
            // A preference saved while this Mac was offline must be written
            // back after the field-wise merge. Otherwise it would look
            // correct locally but never reach the iPhone.
            resolvedPreferences = merged == remote
                ? merged
                : try await cloudPreferences.save(merged)
        } else {
            resolvedPreferences = try await cloudPreferences.save(localPreferences)
        }
        let stablePreferences = try await reconcileSharedPreferences(
            resolvedPreferences,
            observedMutationVersion: observedMutationVersion,
            using: cloudPreferences
        )
        storeSharedPreferences(stablePreferences)
        return stablePreferences
    }

    private func publishSharedPreferences(
        using cloudPreferences: any SharedPreferencesCloudStoring
    ) async throws -> SharedPreferences {
        try await acquireSharedPreferencesOperation()
        defer { sharedPreferencesOperationInProgress = false }

        let observedMutationVersion = sharedPreferenceMutationVersion
        let saved = try await cloudPreferences.save(sharedPreferences())
        let stablePreferences = try await reconcileSharedPreferences(
            saved,
            observedMutationVersion: observedMutationVersion,
            using: cloudPreferences
        )
        storeSharedPreferences(stablePreferences)
        return stablePreferences
    }

    private func reconcileSharedPreferences(
        _ initialPreferences: SharedPreferences,
        observedMutationVersion initialMutationVersion: UInt64,
        using cloudPreferences: any SharedPreferencesCloudStoring
    ) async throws -> SharedPreferences {
        var preferences = initialPreferences
        var observedMutationVersion = initialMutationVersion

        while true {
            let mutations = sharedPreferenceMutations(after: observedMutationVersion)
            if mutations.latestVersion > 0 {
                apply(mutations, to: &preferences)
                let includedMutationVersion = sharedPreferenceMutationVersion
                preferences = try await cloudPreferences.save(preferences)
                observedMutationVersion = includedMutationVersion
                continue
            }

            observedMutationVersion = sharedPreferenceMutationVersion
            try await applySharedPreferences(preferences)
            if sharedPreferenceMutationVersion == observedMutationVersion {
                return preferences
            }
        }
    }

    private func sharedPreferenceMutations(
        after version: UInt64
    ) -> SharedPreferenceMutationRecord {
        var result = SharedPreferenceMutationRecord()
        if let mutation = sharedPreferenceMutations.selectedFrame,
           mutation.version > version {
            result.selectedFrame = mutation
        }
        if let mutation = sharedPreferenceMutations.dryRun,
           mutation.version > version {
            result.dryRun = mutation
        }
        if let mutation = sharedPreferenceMutations.syncInterval,
           mutation.version > version {
            result.syncInterval = mutation
        }
        return result
    }

    private func apply(
        _ mutations: SharedPreferenceMutationRecord,
        to preferences: inout SharedPreferences
    ) {
        let installationID = cloudInstallationID
        if let mutation = mutations.selectedFrame {
            preferences.setSelectedFrameID(
                mutation.value,
                at: mutation.modifiedAt,
                by: installationID
            )
        }
        if let mutation = mutations.dryRun {
            preferences.setDryRun(
                mutation.value,
                at: mutation.modifiedAt,
                by: installationID
            )
        }
        if let mutation = mutations.syncInterval {
            preferences.setPreferredSyncInterval(
                mutation.value,
                at: mutation.modifiedAt,
                by: installationID
            )
        }
    }

    private func acquireSharedPreferencesOperation() async throws {
        while sharedPreferencesOperationInProgress {
            try Task.checkCancellation()
            try await ContinuousClock().sleep(for: .milliseconds(100))
        }
        sharedPreferencesOperationInProgress = true
    }

    func applySharedPreferences(_ preferences: SharedPreferences) async throws {
        try await waitForSharedPreferencesApplyWindow()
        let priorDryRun = configuration.dryRun
        let priorInterval = configuration.syncIntervalMinutes
        var changed = false
        if configuration.dryRun != preferences.dryRun {
            configuration.dryRun = preferences.dryRun
            changed = true
        }
        if configuration.syncIntervalMinutes != preferences.preferredSyncIntervalMinutes {
            configuration.syncIntervalMinutes = preferences.preferredSyncIntervalMinutes
            changed = true
        }
        let selectedFrameID = preferences.selectedFrameID.trimmed
        if !selectedFrameID.isEmpty,
           configuration.account.frameID != selectedFrameID {
            guard await selectFrame(
                selectedFrameID,
                replacing: configuration.account.frameID,
                recordSharedPreferenceMutation: false
            ) else {
                configuration.dryRun = priorDryRun
                configuration.syncIntervalMinutes = priorInterval
                throw SharedPreferencesApplicationError.frameSelectionFailed(selectedFrameID)
            }
            return
        }
        if changed, !saveConfiguration(publishSharedState: false) {
            configuration.dryRun = priorDryRun
            configuration.syncIntervalMinutes = priorInterval
            throw SharedPreferencesApplicationError.persistenceFailed
        }
    }

    /// CloudKit requests can outlive the operation that launched them. Wait
    /// for account and sync ownership before applying their result, rather
    /// than dropping a user change or mutating a live sync configuration.
    private func waitForSharedPreferencesApplyWindow() async throws {
        while isConnecting || isSyncing {
            try Task.checkCancellation()
            try await ContinuousClock().sleep(for: .milliseconds(100))
        }
    }

    private func publishLocalSelectedPhotoMappings(
        intentionalPhotoAdditions: [UUID: Set<String>] = [:]
    ) async throws {
        guard photosAuthorizationStatus == .fullAccess else { return }
        let cloudMappings = CloudPhotoMappingStore()
        for mapping in configuration.photoMappings where mapping.sourceKind == .selectedPhotos {
            let shared = sharedPhotoMapping(for: mapping)
            let savedMapping = try await cloudMappings.saveMapping(shared)
            cacheSharedPhotoMapping(savedMapping)

            let cloudIdentifiers = try photoLibrary.cloudAssetIdentifiers(
                for: Array(mapping.selectedAssetIDs)
            )
            let remoteSelections = try await cloudMappings.loadSelections(for: mapping.id)
            let remoteSelectionByCloudIdentifier = Dictionary(
                uniqueKeysWithValues: remoteSelections.map {
                    ($0.cloudAssetIdentifier, $0)
                }
            )
            let explicitlyAddedLocalIdentifiers = intentionalPhotoAdditions[mapping.id] ?? []
            for (localIdentifier, cloudIdentifier) in cloudIdentifiers {
                guard SharedPhotoSelection.shouldPublishAdd(
                    for: remoteSelectionByCloudIdentifier[cloudIdentifier],
                    isExplicitUserAddition: explicitlyAddedLocalIdentifiers.contains(localIdentifier)
                ) else {
                    continue
                }
                _ = try await cloudMappings.saveSelection(
                    .adding(
                        mappingID: mapping.id,
                        cloudAssetIdentifier: cloudIdentifier,
                        at: .now,
                        by: cloudInstallationID
                    )
                )
            }
        }
    }

    private func publishRemovedSelectedPhotos(
        _ localAssetIDs: Set<String>,
        for mapping: PhotoMapping
    ) async {
        guard !localAssetIDs.isEmpty, photosAuthorizationStatus == .fullAccess else { return }
        do {
            let cloudIdentifiers = try photoLibrary.cloudAssetIdentifiers(for: Array(localAssetIDs))
            let cloudMappings = CloudPhotoMappingStore()
            for cloudIdentifier in cloudIdentifiers.values {
                _ = try await cloudMappings.saveSelection(
                    .removing(
                        mappingID: mapping.id,
                        cloudAssetIdentifier: cloudIdentifier,
                        at: .now,
                        by: cloudInstallationID
                    )
                )
            }
        } catch {
            if SharedCloudKitFailure.isProductionSchemaConfigurationError(error) {
                recordSharediCloudFailure(error, savedLocally: true)
                return
            }
            appendActivity(.init(
                level: .warning,
                area: .photos,
                message: "Could not remove selected photos from the iCloud list: \(error.localizedDescription)"
            ))
        }
    }

    private func importSharedPhotoMappings() async throws {
        guard photosAuthorizationStatus == .fullAccess else { return }
        let cloudMappings = CloudPhotoMappingStore()
        let remoteMappings = try await cloudMappings.loadMappings()
        var didChange = false

        for shared in remoteMappings where !configuration.retiredPhotoMappingIDs.contains(shared.id) {
            let selections = try await cloudMappings.loadSelections(for: shared.id)
            let activeCloudIdentifiers = selections
                .filter(\.isIncluded)
                .map(\.cloudAssetIdentifier)
            let localIdentifiers = try photoLibrary.localAssetIdentifiers(
                for: activeCloudIdentifiers
            )

            if let index = configuration.photoMappings.firstIndex(where: { $0.id == shared.id }) {
                var mapping = configuration.photoMappings[index]
                guard mapping.sourceKind == .selectedPhotos else { continue }
                apply(shared, to: &mapping)
                reconcile(
                    selections: selections,
                    localIdentifiers: localIdentifiers,
                    into: &mapping
                )
                if configuration.photoMappings[index] != mapping {
                    configuration.photoMappings[index] = mapping
                    didChange = true
                }
            } else {
                var mapping = photoMapping(from: shared)
                mapping.selectedAssetIDs = Set(localIdentifiers.values)
                configuration.photoMappings.append(mapping)
                didChange = true
            }
            cacheSharedPhotoMapping(shared)
        }

        if didChange {
            saveConfiguration(triggerSync: true)
        }
    }

    private func reconcile(
        selections: [SharedPhotoSelection],
        localIdentifiers: [String: String],
        into mapping: inout PhotoMapping
    ) {
        let selectionByCloudIdentifier = Dictionary(
            uniqueKeysWithValues: selections.map { ($0.cloudAssetIdentifier, $0) }
        )
        let existingCloudIdentifiers = (try? photoLibrary.cloudAssetIdentifiers(
            for: Array(mapping.selectedAssetIDs)
        )) ?? [:]

        mapping.selectedAssetIDs.formUnion(localIdentifiers.values)
        for (localIdentifier, cloudIdentifier) in existingCloudIdentifiers {
            if let selection = selectionByCloudIdentifier[cloudIdentifier], !selection.isIncluded {
                mapping.selectedAssetIDs.remove(localIdentifier)
            }
        }
    }

    private func sharedPhotoMapping(for mapping: PhotoMapping) -> SharedPhotoMapping {
        if let cached = cachedSharedPhotoMappings()[mapping.id], cached.matchesPortableFields(of: mapping) {
            return cached
        }
        return SharedPhotoMapping.portable(
            from: mapping,
            modifiedByInstallationID: cloudInstallationID
        )
    }

    private func photoMapping(from shared: SharedPhotoMapping) -> PhotoMapping {
        shared.localPhotoMapping()
    }

    private func apply(_ shared: SharedPhotoMapping, to mapping: inout PhotoMapping) {
        shared.applyPortableFields(to: &mapping)
    }

    private var cloudInstallationID: String {
        let key = "cloud-installation-id"
        if let identifier = UserDefaults.standard.string(forKey: key), !identifier.isEmpty {
            return identifier
        }
        let identifier = UUID().uuidString.lowercased()
        UserDefaults.standard.set(identifier, forKey: key)
        return identifier
    }

    private func loadSharedPreferences() -> SharedPreferences {
        let key = "shared-preferences-v1"
        if let data = UserDefaults.standard.data(forKey: key),
           let preferences = try? JSONDecoder().decode(SharedPreferences.self, from: data) {
            return preferences
        }
        return SharedPreferences(modifiedByInstallationID: cloudInstallationID)
    }

    private func storeSharedPreferences(_ preferences: SharedPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: "shared-preferences-v1")
    }

    private func cachedSharedPhotoMappings() -> [UUID: SharedPhotoMapping] {
        let key = "shared-photo-mappings-v1"
        guard let data = UserDefaults.standard.data(forKey: key),
              let mappings = try? JSONDecoder().decode([SharedPhotoMapping].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: mappings.map { ($0.id, $0) })
    }

    private func cacheSharedPhotoMapping(_ mapping: SharedPhotoMapping) {
        var mappings = cachedSharedPhotoMappings()
        mappings[mapping.id] = mapping
        guard let data = try? JSONEncoder().encode(Array(mappings.values)) else { return }
        UserDefaults.standard.set(data, forKey: "shared-photo-mappings-v1")
    }
}

extension SharedPhotoMapping {
    /// Album IDs are scoped to one Skylight frame, while selected-photo
    /// mappings are shared across devices without a frame field. Share the
    /// human-readable title and portable settings only. The active Mac
    /// resolves the destination from its frame-scoped sync state or title.
    static func portable(
        from mapping: PhotoMapping,
        modifiedByInstallationID: String
    ) -> SharedPhotoMapping {
        SharedPhotoMapping(
            id: mapping.id,
            name: mapping.name,
            destinationAlbumID: nil,
            destinationAlbumTitle: mapping.destinationAlbumTitle,
            removalPolicy: mapping.removalPolicy.sharedCloudValue,
            maximumLongEdge: mapping.maximumLongEdge,
            jpegQuality: mapping.jpegQuality,
            isEnabled: mapping.enabled,
            modifiedByInstallationID: modifiedByInstallationID
        )
    }

    static func portableRetirement(
        from mapping: PhotoMapping,
        at date: Date = .now,
        modifiedByInstallationID: String
    ) -> SharedPhotoMapping {
        var retired = portable(
            from: mapping,
            modifiedByInstallationID: modifiedByInstallationID
        )
        retired.isEnabled = false
        retired.modifiedAt = date
        return retired
    }

    func localPhotoMapping() -> PhotoMapping {
        PhotoMapping(
            id: id,
            name: name,
            sourceKind: .selectedPhotos,
            sourceCollectionID: nil,
            sourceCollectionTitle: nil,
            selectedAssetIDs: [],
            destinationAlbumID: nil,
            destinationAlbumTitle: destinationAlbumTitle,
            removalPolicy: removalPolicy.localValue,
            maximumLongEdge: maximumLongEdge,
            jpegQuality: jpegQuality,
            enabled: isEnabled
        )
    }

    func applyPortableFields(to mapping: inout PhotoMapping) {
        mapping.name = name
        // Preserve the receiver's frame-scoped destination ID. A remote value
        // may belong to a different frame and must never be imported.
        mapping.destinationAlbumTitle = destinationAlbumTitle
        mapping.removalPolicy = removalPolicy.localValue
        mapping.maximumLongEdge = maximumLongEdge
        mapping.jpegQuality = jpegQuality
        mapping.enabled = isEnabled
    }

    func matchesPortableFields(of mapping: PhotoMapping) -> Bool {
        id == mapping.id &&
            name == mapping.name &&
            destinationAlbumID == nil &&
            destinationAlbumTitle == mapping.destinationAlbumTitle &&
            removalPolicy == mapping.removalPolicy.sharedCloudValue &&
            maximumLongEdge == mapping.maximumLongEdge &&
            jpegQuality == mapping.jpegQuality &&
            isEnabled == mapping.enabled
    }
}

private extension ManagedRemovalPolicy {
    var sharedCloudValue: SharedPhotoRemovalPolicy {
        switch self {
        case .keepOnSkylight: .keepOnSkylight
        case .removeFromSkylight: .removeFromSkylight
        }
    }
}

private extension SharedPhotoRemovalPolicy {
    var localValue: ManagedRemovalPolicy {
        switch self {
        case .keepOnSkylight: .keepOnSkylight
        case .removeFromSkylight: .removeFromSkylight
        }
    }
}
