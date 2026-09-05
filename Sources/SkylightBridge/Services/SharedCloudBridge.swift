import Foundation
import SkylightBridgeShared

enum SharedPreferencesApplicationError: Error, LocalizedError, Equatable {
    case frameSelectionFailed(String)
    case persistenceFailed
    case selectedPhotoChangesPending(Int)

    var errorDescription: String? {
        switch self {
        case let .frameSelectionFailed(frameID):
            "The shared Skylight frame \(frameID) could not be selected and loaded."
        case .persistenceFailed:
            "The shared preferences could not be saved locally."
        case let .selectedPhotoChangesPending(count):
            "\(count) selected-photo iCloud change\(count == 1 ? " is" : "s are") still pending and will retry during the next shared-state refresh."
        }
    }
}

/// Connects the intentionally small CloudKit contract to macOS-only app
/// configuration. Apple Notes, credentials, device IDs, local sync links, and
/// activity never leave this Mac.
@MainActor
extension AppStore {
    var cloudSync: CloudSyncDriver {
        if let sharedCloudDriver { return sharedCloudDriver }
        let driver = CloudSyncDriver(
            lastSuccessAt: configuration.lastCloudSyncAt,
            retryNotBefore: configuration.cloudRetryNotBefore,
            checkpoint: { [weak self] success, retry in
                guard let self else { throw CancellationError() }
                let previous = (self.configuration.lastCloudSyncAt, self.configuration.cloudRetryNotBefore)
                self.configuration.lastCloudSyncAt = success
                self.configuration.cloudRetryNotBefore = retry
                do { try self.persistConfiguration() }
                catch {
                    (self.configuration.lastCloudSyncAt, self.configuration.cloudRetryNotBefore) = previous
                    throw error
                }
            }
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            do { try await self.performSharediCloudRefresh() }
            catch { self.recordSharediCloudFailure(error, savedLocally: true, updateDriver: false); throw error }
        }
        sharedCloudDriver = driver
        return driver
    }

    var pendingCloudChangeCount: Int {
        pendingSharedPhotoChanges.changeCount + configuration.pendingPhotoMappingRetirements.count +
            (configuration.sharedPreferencesPending ? 1 : 0)
    }

    var cloudStatusMessage: String {
        if cloudSync.isSyncing { return "Sharing changes with iCloud…" }
        if let error = cloudSync.errorMessage { return error }
        if pendingCloudChangeCount > 0 { return "Saved on this Mac. Changes are waiting for iCloud." }
        return !cloudSync.hasCompletedRefresh ? "Waiting to connect to iCloud." : "Up to date with iCloud."
    }

    func refreshSharediCloudState() async {
        guard configurationLoadError == nil else { return }
        await cloudSync.syncNow()
    }

    func performSharediCloudRefresh() async throws {
        guard configurationLoadError == nil else { throw SharedPreferencesApplicationError.persistenceFailed }
        try await acquireSharedCloudOperationInApplyWindow()
        defer { sharedCloudOperationInProgress = false }
        hasLoadedSharediCloudState = false
        var errors = await retryPendingPhotoMappingRetirements()
        if errors.contains(where: CloudRetryPolicy.shouldStopBatch) { throw CloudOperationErrors(errors) }
        do {
            _ = try await refreshSharedPreferences(using: sharedPreferencesStore)
            hasLoadedSharediCloudState = true
        } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
        let version = sharedPreferenceMutationVersion
        if FeatureFlags.multiDeviceCoordinationEnabled {
            do { try await publishAndCheckHeartbeat() } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
        } else { multiClientWarning = nil }
        do { try await importSharedPhotoMappings() } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
        do { try await publishPendingSelectedPhotoChanges() } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
        if sharedPreferenceMutationVersion != version {
            do { _ = try await publishSharedPreferences(using: sharedPreferencesStore) } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
        }
        if !errors.isEmpty { throw CloudOperationErrors(errors) }
        guard pendingCloudChangeCount == 0 else {
            throw SharedPreferencesApplicationError.selectedPhotoChangesPending(pendingCloudChangeCount)
        }
        recordSharediCloudSuccess()
        statusMessage = "Shared preferences and selected photos are up to date with iCloud."
    }

    @discardableResult
    func publishSharediCloudState() async -> Bool {
        guard configurationLoadError == nil else { return false }
        guard !cloudSync.isRetryDelayed else { cloudSync.request(); return false }
        do {
            try await acquireSharedCloudOperationInApplyWindow()
            defer { sharedCloudOperationInProgress = false }
            var errors = await retryPendingPhotoMappingRetirements()
        if errors.contains(where: CloudRetryPolicy.shouldStopBatch) { throw CloudOperationErrors(errors) }
            do { _ = try await publishSharedPreferences(
                using: sharedPreferencesStore
            ) } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
            do { try await publishPendingSelectedPhotoChanges() } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
            if !errors.isEmpty { throw CloudOperationErrors(errors) }
            guard pendingCloudChangeCount == 0 else {
                throw SharedPreferencesApplicationError.selectedPhotoChangesPending(pendingCloudChangeCount)
            }
            cloudSync.request()
            recordSharediCloudSuccess()
            return true
        } catch {
            recordSharediCloudFailure(error, savedLocally: true)
            return false
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

    private func recordSharediCloudFailure(_ error: any Error, savedLocally: Bool, updateDriver: Bool = true) {
        if updateDriver { cloudSync.recordFailure(error) }
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

    @discardableResult
    func setPhotoMappingEnabled(_ mappingID: UUID, enabled: Bool) -> Bool {
        guard var mapping = configuration.photoMappings.first(where: { $0.id == mappingID }) else {
            return false
        }
        mapping.enabled = enabled
        return savePhotoMapping(mapping)
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
        let wasSharedSelectedPhotos = previous?.sourceKind == .selectedPhotos
        let isSharedSelectedPhotos = mapping.sourceKind == .selectedPhotos
        if isSharedSelectedPhotos {
            configuration.retiredPhotoMappingIDs.remove(mapping.id)
            configuration.pendingPhotoMappingRetirements.removeAll { $0.id == mapping.id }
        } else if wasSharedSelectedPhotos, let previous {
            configuration.retiredPhotoMappingIDs.insert(mapping.id)
            configuration.pendingPhotoMappingRetirements.removeAll { $0.id == mapping.id }
            configuration.pendingPhotoMappingRetirements.append(previous)
            configuration.photoRetirementDates = configuration.photoRetirementDates ?? [:]
            configuration.photoRetirementDates?[mapping.id] = .now
        }
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
        if isSharedSelectedPhotos {
            pendingSharedPhotoChanges.recordPortableMapping(mapping)
            pendingSharedPhotoChanges.record(
                mappingID: mapping.id,
                additions: mapping.selectedAssetIDs.subtracting(previous?.selectedAssetIDs ?? []),
                removals: (previous?.selectedAssetIDs ?? []).subtracting(mapping.selectedAssetIDs)
            )
        } else {
            pendingSharedPhotoChanges.discard(mappingID: mapping.id)
        }
        guard saveConfiguration(
            triggerSync: triggerSync,
            publishSharedState: !isSharedSelectedPhotos && !wasSharedSelectedPhotos
        ) else {
            configuration = previousConfiguration
            return false
        }

        guard isSharedSelectedPhotos else {
            if wasSharedSelectedPhotos, let previous {
                Task { await retireSharedPhotoMapping(previous) }
            }
            return true
        }
        cloudSync.request()
        return true
    }

    /// The shared package has no mapping-delete operation. Publish a newer
    /// disabled record so existing and newly connected devices stop syncing
    /// the retired mapping, while the local suppression set prevents reimport.
    func retireSharedPhotoMapping(_ mapping: PhotoMapping) async {
        guard !cloudSync.isRetryDelayed else { cloudSync.request(); return }
        do {
            try await acquireSharedCloudOperation()
            defer { sharedCloudOperationInProgress = false }
            guard !cloudSync.isRetryDelayed else { cloudSync.request(); return }
            try await retireSharedPhotoMappingWithinOperation(mapping)
            if configuration.pendingPhotoMappingRetirements.contains(where: { $0.id == mapping.id }) {
                throw SharedPreferencesApplicationError.selectedPhotoChangesPending(1)
            }
            cloudSync.request()
        } catch is CancellationError {
            // The durable pending retirement remains for the next refresh.
        } catch {
            recordSharediCloudFailure(error, savedLocally: true)
        }
    }

    private func retireSharedPhotoMappingWithinOperation(_ mapping: PhotoMapping) async throws {
        guard mapping.sourceKind == .selectedPhotos,
              configuration.retiredPhotoMappingIDs.contains(mapping.id),
              configuration.pendingPhotoMappingRetirements.contains(mapping) else { return }
        if configuration.photoRetirementDates?[mapping.id] == nil {
            configuration.photoRetirementDates = configuration.photoRetirementDates ?? [:]
            configuration.photoRetirementDates?[mapping.id] = .now
            try persistConfiguration()
        }
        var retired = SharedPhotoMapping.portableRetirement(from: mapping, modifiedByInstallationID: cloudInstallationID)
        retired.modifiedAt = configuration.photoRetirementDates?[mapping.id] ?? retired.modifiedAt
        let saved = try await sharedPhotoMappingStore.saveMapping(retired)
        guard configuration.photoRetirementDates?[mapping.id] == retired.modifiedAt,
              configuration.pendingPhotoMappingRetirements.contains(mapping),
              configuration.retiredPhotoMappingIDs.contains(mapping.id) else { return }
        cacheSharedPhotoMapping(saved)
        if saved.isEnabled, saved.modifiedAt > retired.modifiedAt {
            let previous = configuration
            configuration.retiredPhotoMappingIDs.remove(mapping.id)
            configuration.pendingPhotoMappingRetirements.removeAll { $0.id == mapping.id }
            do { try persistConfiguration() }
            catch { configuration = previous; throw error }
        } else {
            acknowledgePhotoMappingRetirement(mapping.id, savedRecordIsEnabled: saved.isEnabled)
        }
    }

    private func retryPendingPhotoMappingRetirements() async -> [any Error] {
        var errors: [any Error] = []
        for mapping in configuration.pendingPhotoMappingRetirements {
            do { try await retireSharedPhotoMappingWithinOperation(mapping) }
            catch {
                errors.append(error)
                if CloudRetryPolicy.shouldStopBatch(error) { break }
            }
        }
        return errors
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

    private func sharedPreferences() throws -> SharedPreferences {
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
        if configuration.sharedPreferences != preferences {
            try storeSharedPreferences(preferences, pending: true)
        }
        return preferences
    }

    func refreshSharedPreferences(
        using cloudPreferences: any SharedPreferencesCloudStoring
    ) async throws -> SharedPreferences {
        try await acquireSharedPreferencesOperation()
        defer { sharedPreferencesOperationInProgress = false }

        let observedMutationVersion = sharedPreferenceMutationVersion
        let localPreferences = try sharedPreferences()
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
        try storeSharedPreferences(stablePreferences)
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
        try storeSharedPreferences(stablePreferences)
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

    private func acquireSharedCloudOperation() async throws {
        while sharedCloudOperationInProgress {
            try Task.checkCancellation()
            try await ContinuousClock().sleep(for: .milliseconds(100))
        }
        sharedCloudOperationInProgress = true
    }

    /// Takes the shared Cloud operation gate, but only while the apply window
    /// is open.
    ///
    /// Waiting for the window from inside the gate inverts the two locks. A
    /// teardown takes them the other way round: it sets `isSyncing` first and
    /// then wants the gate, so a publish holding the gate and waiting on
    /// `isSyncing` can never be satisfied. Holding the gate through that wait
    /// also strands every unrelated Cloud operation, including a mapping
    /// retirement that never touches the window at all.
    ///
    /// Waiting first and taking the gate second removes the cycle. The window
    /// can still close between the two steps, so release the gate and start
    /// over rather than proceeding across a sync.
    private func acquireSharedCloudOperationInApplyWindow() async throws {
        while true {
            try await waitForSharedPreferencesApplyWindow()
            try await acquireSharedCloudOperation()
            if !isConnecting, !isSyncing { return }
            sharedCloudOperationInProgress = false
            try Task.checkCancellation()
            try await ContinuousClock().sleep(for: .milliseconds(100))
        }
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

    private func publishPendingSelectedPhotoChanges() async throws {
        let previousPending = pendingSharedPhotoChanges
        pendingSharedPhotoChanges.materializeOperationDates()
        if pendingSharedPhotoChanges != previousPending {
            do { try persistConfiguration() }
            catch { pendingSharedPhotoChanges = previousPending; throw error }
        }
        guard photosAuthorizationStatus == .fullAccess else {
            if !pendingSharedPhotoChanges.isEmpty {
                throw SharedPreferencesApplicationError.selectedPhotoChangesPending(
                    pendingSharedPhotoChanges.changeCount
                )
            }
            return
        }

        repeat {
            let pending = pendingSharedPhotoChanges
            var configurationChanged = false
            for index in configuration.photoMappings.indices {
                var mapping = pending.applyingPortableFields(
                    to: configuration.photoMappings[index]
                )
                guard mapping.sourceKind == .selectedPhotos else { continue }
                let reconciledAssetIDs = pending.applying(
                    to: mapping.selectedAssetIDs,
                    mappingID: mapping.id
                )
                mapping.selectedAssetIDs = reconciledAssetIDs
                if mapping != configuration.photoMappings[index] {
                    configuration.photoMappings[index] = mapping
                    configurationChanged = true
                }
            }
            if configurationChanged,
               !saveConfiguration(publishSharedState: false) {
                throw SharedPreferencesApplicationError.persistenceFailed
            }

            let (published, publicationErrors) = await publishLocalSelectedPhotoMappings(pending: pending)
            var acknowledged = published
            var errors = publicationErrors
            for (mappingID, localAssetIDs) in pending.removals {
                if errors.contains(where: CloudRetryPolicy.shouldStopBatch) { break }
                let (resolved, failures) = await publishRemovedSelectedPhotos(localAssetIDs, mappingID: mappingID, pending: pending)
                if !resolved.isEmpty { acknowledged.removals[mappingID] = resolved }
                errors += failures
            }
            let beforeAcknowledgment = pendingSharedPhotoChanges
            pendingSharedPhotoChanges.acknowledge(acknowledged)
            if pendingSharedPhotoChanges != beforeAcknowledgment,
               !saveConfiguration(publishSharedState: false) {
                pendingSharedPhotoChanges = beforeAcknowledgment
                throw SharedPreferencesApplicationError.persistenceFailed
            }
            if !errors.isEmpty { throw CloudOperationErrors(errors) }
            if pendingSharedPhotoChanges.isEmpty {
                return
            }

            // PhotoKit can omit identifiers it cannot currently translate.
            // Retain those intents for a later operation instead of spinning
            // here or claiming that an unpublished change reached CloudKit.
            guard acknowledged.additions == pending.additions,
                  acknowledged.removals == pending.removals,
                  acknowledged.portableMappings == pending.portableMappings else {
                throw SharedPreferencesApplicationError.selectedPhotoChangesPending(
                    pendingSharedPhotoChanges.changeCount
                )
            }
        } while !pendingSharedPhotoChanges.isEmpty
    }

    private func publishLocalSelectedPhotoMappings(
        pending: PendingSharedPhotoChanges
    ) async -> (PendingSharedPhotoChanges, [any Error]) {
        guard photosAuthorizationStatus == .fullAccess else { return (.init(), []) }
        var acknowledged = PendingSharedPhotoChanges()
        acknowledged.operationDates = pending.operationDates
        acknowledged.mappingDates = pending.mappingDates
        var errors: [any Error] = []
        let mappingIDs = configuration.photoMappings
            .filter { $0.sourceKind == .selectedPhotos }
            .map(\.id)
        for mappingID in mappingIDs {
            do {
            guard !configuration.retiredPhotoMappingIDs.contains(mappingID),
                  var mapping = configuration.photoMappings.first(where: {
                      $0.id == mappingID && $0.sourceKind == .selectedPhotos
                  }) else { continue }
            mapping = pending.applyingPortableFields(to: mapping)
            mapping.selectedAssetIDs = pending.applying(
                to: mapping.selectedAssetIDs,
                mappingID: mappingID
            )
            var shared = sharedPhotoMapping(for: mapping)
            if let date = pending.mappingDates?[mappingID] { shared.modifiedAt = date }
            let savedMapping = try await sharedPhotoMappingStore.saveMapping(shared)
            cacheSharedPhotoMapping(savedMapping)

            guard !configuration.retiredPhotoMappingIDs.contains(mappingID),
                  configuration.photoMappings.contains(where: {
                      $0.id == mappingID && $0.sourceKind == .selectedPhotos
                  }) else { continue }

            let cloudIdentifiers = try sharedPhotoIdentifiers.cloudAssetIdentifiers(
                for: Array(mapping.selectedAssetIDs)
            )
            guard !configuration.retiredPhotoMappingIDs.contains(mappingID),
                  configuration.photoMappings.contains(where: {
                      $0.id == mappingID && $0.sourceKind == .selectedPhotos
                  }) else { continue }
            let selectionResult = try await sharedPhotoMappingStore.loadSelectionsResult(for: mappingID)
            if !selectionResult.isComplete {
                let error = CloudIncompleteFetchError(failures: selectionResult.failures)
                errors.append(error)
                if CloudRetryPolicy.shouldStopBatch(error) { return (acknowledged, errors) }
            }
            let remoteSelections = selectionResult.values
            let remoteSelectionByCloudIdentifier = Dictionary(
                uniqueKeysWithValues: remoteSelections.map {
                    ($0.cloudAssetIdentifier, $0)
                }
            )
            let explicitlyAddedLocalIdentifiers = pending.additions[mappingID] ?? []
            var resolvedAdditions = Set<String>()
            for (localIdentifier, cloudIdentifier) in cloudIdentifiers {
                guard !configuration.retiredPhotoMappingIDs.contains(mappingID),
                      configuration.photoMappings.contains(where: {
                          $0.id == mappingID && $0.sourceKind == .selectedPhotos
                      }) else { break }
                if !selectionResult.isComplete,
                   remoteSelectionByCloudIdentifier[cloudIdentifier] == nil,
                   !explicitlyAddedLocalIdentifiers.contains(localIdentifier) { continue }
                guard SharedPhotoSelection.shouldPublishAdd(
                    for: remoteSelectionByCloudIdentifier[cloudIdentifier],
                    isExplicitUserAddition: explicitlyAddedLocalIdentifiers.contains(localIdentifier)
                ) else {
                    continue
                }
                do {
                let savedSelection = try await sharedPhotoMappingStore.saveSelection(
                    .adding(
                        mappingID: mappingID,
                        cloudAssetIdentifier: cloudIdentifier,
                        at: pending.operationDate(mappingID: mappingID, assetID: localIdentifier, removing: false) ?? shared.modifiedAt,
                        by: cloudInstallationID
                    )
                )
                try applyPublishedSelection(savedSelection, localIdentifier: localIdentifier, pending: pending)
                if explicitlyAddedLocalIdentifiers.contains(localIdentifier) {
                    resolvedAdditions.insert(localIdentifier)
                    acknowledged.additions[mappingID, default: []].insert(localIdentifier)
                }
                } catch {
                    errors.append(error)
                    if CloudRetryPolicy.shouldStopBatch(error) { return (acknowledged, errors) }
                }
            }
            if !resolvedAdditions.isEmpty {
                acknowledged.additions[mappingID] = resolvedAdditions
            }
            if let portableMapping = pending.portableMappings[mappingID] {
                try applyPublishedMapping(savedMapping, pending: pending)
                acknowledged.portableMappings[mappingID] = portableMapping
            }
            } catch {
                errors.append(error)
                if CloudRetryPolicy.shouldStopBatch(error) { return (acknowledged, errors) }
            }
        }
        return (acknowledged, errors)
    }

    private func publishRemovedSelectedPhotos(
        _ localAssetIDs: Set<String>,
        mappingID: UUID,
        pending: PendingSharedPhotoChanges
    ) async -> (Set<String>, [any Error]) {
        var resolved = Set<String>()
        var errors: [any Error] = []
        do {
            let identifiers = try sharedPhotoIdentifiers.cloudAssetIdentifiers(for: Array(localAssetIDs))
            for (localIdentifier, cloudIdentifier) in identifiers {
                do {
                    let saved = try await sharedPhotoMappingStore.saveSelection(.removing(
                        mappingID: mappingID, cloudAssetIdentifier: cloudIdentifier,
                        at: pending.operationDate(mappingID: mappingID, assetID: localIdentifier, removing: true) ?? .distantPast,
                        by: cloudInstallationID))
                    try applyPublishedSelection(saved, localIdentifier: localIdentifier, pending: pending)
                    resolved.insert(localIdentifier)
                } catch {
                    errors.append(error)
                    if CloudRetryPolicy.shouldStopBatch(error) { return (resolved, errors) }
                }
            }
        } catch { errors.append(error) }
        return (resolved, errors)
    }

    /// A successful cloud save already merged the submitted operation. A
    /// later remote operation may win. Apply it only if the user has not made
    /// another edit while this request was suspended.
    func applyPublishedSelection(_ saved: SharedPhotoSelection, localIdentifier: String, pending: PendingSharedPhotoChanges) throws {
        let id = saved.mappingID
        for removing in [false, true] {
            guard pending.operationDate(mappingID: id, assetID: localIdentifier, removing: removing) ==
                pendingSharedPhotoChanges.operationDate(mappingID: id, assetID: localIdentifier, removing: removing) else { return }
        }
        guard !configuration.retiredPhotoMappingIDs.contains(id),
              let index = configuration.photoMappings.firstIndex(where: { $0.id == id && $0.sourceKind == .selectedPhotos }) else { return }
        let previous = configuration.photoMappings[index]
        if saved.isIncluded { configuration.photoMappings[index].selectedAssetIDs.insert(localIdentifier) }
        else { configuration.photoMappings[index].selectedAssetIDs.remove(localIdentifier) }
        do { try persistConfiguration() }
        catch { configuration.photoMappings[index] = previous; throw error }
    }

    func applyPublishedMapping(_ saved: SharedPhotoMapping, pending: PendingSharedPhotoChanges) throws {
        guard pendingSharedPhotoChanges.portableMappings[saved.id] == pending.portableMappings[saved.id],
              pendingSharedPhotoChanges.mappingDates?[saved.id] == pending.mappingDates?[saved.id],
              !configuration.retiredPhotoMappingIDs.contains(saved.id),
              let index = configuration.photoMappings.firstIndex(where: { $0.id == saved.id && $0.sourceKind == .selectedPhotos }) else { return }
        let previous = configuration.photoMappings[index]
        saved.applyPortableFields(to: &configuration.photoMappings[index])
        do { try persistConfiguration() }
        catch { configuration.photoMappings[index] = previous; throw error }
    }

    private func importSharedPhotoMappings() async throws {
        guard photosAuthorizationStatus == .fullAccess else { return }
        let remote = try await sharedPhotoMappingStore.loadMappingsResult()
        var errors: [any Error] = remote.isComplete ? [] : [CloudIncompleteFetchError(failures: remote.failures)]
        if errors.contains(where: CloudRetryPolicy.shouldStopBatch) { throw CloudOperationErrors(errors) }
        for shared in remote.values {
            do {
            if configuration.retiredPhotoMappingIDs.contains(shared.id) {
                guard shared.isEnabled, let retiredAt = configuration.photoRetirementDates?[shared.id],
                      shared.modifiedAt > retiredAt else { continue }
                let previous = configuration
                configuration.retiredPhotoMappingIDs.remove(shared.id)
                configuration.pendingPhotoMappingRetirements.removeAll { $0.id == shared.id }
                do { try persistConfiguration() }
                catch { configuration = previous; throw error }
            }
            let result = try await sharedPhotoMappingStore.loadSelectionsResult(for: shared.id)
            if !result.isComplete {
                let error = CloudIncompleteFetchError(failures: result.failures)
                if CloudRetryPolicy.shouldStopBatch(error) { throw error }
                errors.append(error)
            }
            let selections = result.values
            let activeCloudIdentifiers = selections
                .filter(\.isIncluded)
                .map(\.cloudAssetIdentifier)
            let localIdentifiers = try sharedPhotoIdentifiers.localAssetIdentifiers(
                for: activeCloudIdentifiers
            )
            // The user may remove a mapping while either CloudKit or PhotoKit
            // is resolving it. Do not re-add a mapping retired during an await.
            guard !configuration.retiredPhotoMappingIDs.contains(shared.id) else { continue }

            let previousMappings = configuration.photoMappings
            var didChange = false
            if let index = configuration.photoMappings.firstIndex(where: { $0.id == shared.id }) {
                var mapping = configuration.photoMappings[index]
                guard mapping.sourceKind == .selectedPhotos else { continue }
                apply(shared, to: &mapping)
                mapping = pendingSharedPhotoChanges.applyingPortableFields(to: mapping)
                reconcile(
                    selections: selections,
                    localIdentifiers: localIdentifiers,
                    into: &mapping
                )
                mapping.selectedAssetIDs = pendingSharedPhotoChanges.applying(
                    to: mapping.selectedAssetIDs,
                    mappingID: mapping.id
                )
                if configuration.photoMappings[index] != mapping {
                    configuration.photoMappings[index] = mapping
                    didChange = true
                }
            } else {
                var mapping = photoMapping(from: shared)
                mapping = pendingSharedPhotoChanges.applyingPortableFields(to: mapping)
                mapping.selectedAssetIDs = Set(localIdentifiers.values)
                mapping.selectedAssetIDs = pendingSharedPhotoChanges.applying(
                    to: mapping.selectedAssetIDs,
                    mappingID: mapping.id
                )
                configuration.photoMappings.append(mapping)
                didChange = true
            }
            if didChange {
                do { try persistConfiguration() }
                catch { configuration.photoMappings = previousMappings; throw error }
            }
            cacheSharedPhotoMapping(shared)
            } catch { if CloudRetryPolicy.shouldStopBatch(error) { throw error }; errors.append(error) }
        }
        if !errors.isEmpty { throw CloudOperationErrors(errors) }
    }

    private func reconcile(
        selections: [SharedPhotoSelection],
        localIdentifiers: [String: String],
        into mapping: inout PhotoMapping
    ) {
        let selectionByCloudIdentifier = Dictionary(
            uniqueKeysWithValues: selections.map { ($0.cloudAssetIdentifier, $0) }
        )
        let existingCloudIdentifiers = (try? sharedPhotoIdentifiers.cloudAssetIdentifiers(
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

    var cloudInstallationID: String {
        let key = "cloud-installation-id"
        if let identifier = UserDefaults.standard.string(forKey: key), !identifier.isEmpty {
            return identifier
        }
        let identifier = UUID().uuidString.lowercased()
        UserDefaults.standard.set(identifier, forKey: key)
        return identifier
    }

    func loadSharedPreferences() -> SharedPreferences {
        if let preferences = configuration.sharedPreferences { return preferences }
        let key = "shared-preferences-v1"
        if let data = UserDefaults.standard.data(forKey: key),
           let preferences = try? JSONDecoder().decode(SharedPreferences.self, from: data) {
            return preferences
        }
        return SharedPreferences(modifiedByInstallationID: cloudInstallationID)
    }

    private func storeSharedPreferences(_ preferences: SharedPreferences, pending: Bool = false) throws {
        let previous = configuration.sharedPreferences
        let wasPending = configuration.sharedPreferencesPending
        configuration.sharedPreferences = preferences
        configuration.sharedPreferencesPending = pending
        do { try persistConfiguration() }
        catch {
            configuration.sharedPreferences = previous
            configuration.sharedPreferencesPending = wasPending
            throw error
        }
        UserDefaults.standard.set(try JSONEncoder().encode(preferences), forKey: "shared-preferences-v1")
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
