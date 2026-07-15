import Foundation
import SkylightBridgeShared

/// Connects the intentionally small CloudKit contract to macOS-only app
/// configuration. Apple Notes, credentials, device IDs, local sync links, and
/// activity never leave this Mac.
@MainActor
extension AppStore {
    func refreshSharediCloudState() async {
        defer { hasLoadedSharediCloudState = true }

        do {
            let cloudPreferences = CloudPreferencesStore()
            let localPreferences = sharedPreferences()
            let resolvedPreferences: SharedPreferences
            if let remote = try await cloudPreferences.load() {
                let merged = localPreferences.merging(remote)
                // A preference saved while this Mac was offline must be
                // written back after the field-wise merge. Otherwise it would
                // look correct locally but never reach the iPhone.
                resolvedPreferences = merged == remote
                    ? merged
                    : try await cloudPreferences.save(merged)
            } else {
                resolvedPreferences = try await cloudPreferences.save(localPreferences)
            }
            storeSharedPreferences(resolvedPreferences)
            applySharedPreferences(resolvedPreferences)

            // Import explicit removes before publishing local selections. If a
            // phone removed a photo while this Mac was offline, publishing
            // first would create a newer add record and silently resurrect it.
            try await importSharedPhotoMappings()
            try await publishLocalSelectedPhotoMappings()
            statusMessage = "Shared preferences and selected photos are up to date with iCloud."
        } catch {
            appendActivity(.init(
                level: .warning,
                area: .system,
                message: "iCloud sharing is unavailable: \(error.localizedDescription)"
            ))
        }
    }

    func publishSharediCloudState() async {
        do {
            let cloudPreferences = CloudPreferencesStore()
            let saved = try await cloudPreferences.save(sharedPreferences())
            storeSharedPreferences(saved)
            applySharedPreferences(saved)
            try await publishLocalSelectedPhotoMappings()
        } catch {
            appendActivity(.init(
                level: .warning,
                area: .system,
                message: "Saved on this Mac. iCloud sharing will retry when available: \(error.localizedDescription)"
            ))
        }
    }

    /// Saves a photo mapping and mirrors only individual-photo changes to
    /// CloudKit. Album and Favorites mappings are intentionally device-local.
    func savePhotoMapping(_ mapping: PhotoMapping, triggerSync: Bool = true) {
        let previous = configuration.photoMappings.first { $0.id == mapping.id }
        if let index = configuration.photoMappings.firstIndex(where: { $0.id == mapping.id }) {
            configuration.photoMappings[index] = mapping
        } else {
            configuration.photoMappings.append(mapping)
        }
        saveConfiguration(triggerSync: triggerSync)

        guard mapping.sourceKind == .selectedPhotos else { return }
        let removedAssetIDs = (previous?.selectedAssetIDs ?? []).subtracting(mapping.selectedAssetIDs)
        Task {
            await publishSharediCloudState()
            await publishRemovedSelectedPhotos(removedAssetIDs, for: mapping)
        }
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

    private func applySharedPreferences(_ preferences: SharedPreferences) {
        var changed = false
        if configuration.account.frameID != preferences.selectedFrameID {
            configuration.account.frameID = preferences.selectedFrameID
            // A device belongs to this physical Mac and is deliberately not
            // shared. It will be selected again when the account reconnects.
            configuration.account.deviceID = ""
            changed = true
        }
        if configuration.dryRun != preferences.dryRun {
            configuration.dryRun = preferences.dryRun
            changed = true
        }
        if configuration.syncIntervalMinutes != preferences.preferredSyncIntervalMinutes {
            configuration.syncIntervalMinutes = preferences.preferredSyncIntervalMinutes
            changed = true
        }
        if changed {
            saveConfiguration()
        }
    }

    private func publishLocalSelectedPhotoMappings() async throws {
        guard photosAuthorizationStatus == .fullAccess else { return }
        let cloudMappings = CloudPhotoMappingStore()
        for mapping in configuration.photoMappings where mapping.sourceKind == .selectedPhotos {
            let shared = sharedPhotoMapping(for: mapping)
            let savedMapping = try await cloudMappings.saveMapping(shared)
            cacheSharedPhotoMapping(savedMapping)

            let cloudIdentifiers = try photoLibrary.cloudAssetIdentifiers(
                for: Array(mapping.selectedAssetIDs)
            )
            for cloudIdentifier in cloudIdentifiers.values {
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

        for shared in remoteMappings {
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
        if let cached = cachedSharedPhotoMappings()[mapping.id], cached.matches(mapping) {
            return cached
        }
        return SharedPhotoMapping(
            id: mapping.id,
            name: mapping.name,
            destinationAlbumID: mapping.destinationAlbumID,
            destinationAlbumTitle: mapping.destinationAlbumTitle,
            removalPolicy: mapping.removalPolicy.sharedCloudValue,
            maximumLongEdge: mapping.maximumLongEdge,
            jpegQuality: mapping.jpegQuality,
            isEnabled: mapping.enabled,
            modifiedByInstallationID: cloudInstallationID
        )
    }

    private func photoMapping(from shared: SharedPhotoMapping) -> PhotoMapping {
        PhotoMapping(
            id: shared.id,
            name: shared.name,
            sourceKind: .selectedPhotos,
            sourceCollectionID: nil,
            sourceCollectionTitle: nil,
            selectedAssetIDs: [],
            destinationAlbumID: shared.destinationAlbumID,
            destinationAlbumTitle: shared.destinationAlbumTitle,
            removalPolicy: shared.removalPolicy.localValue,
            maximumLongEdge: shared.maximumLongEdge,
            jpegQuality: shared.jpegQuality,
            enabled: shared.isEnabled
        )
    }

    private func apply(_ shared: SharedPhotoMapping, to mapping: inout PhotoMapping) {
        mapping.name = shared.name
        mapping.destinationAlbumID = shared.destinationAlbumID
        mapping.destinationAlbumTitle = shared.destinationAlbumTitle
        mapping.removalPolicy = shared.removalPolicy.localValue
        mapping.maximumLongEdge = shared.maximumLongEdge
        mapping.jpegQuality = shared.jpegQuality
        mapping.enabled = shared.isEnabled
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

private extension SharedPhotoMapping {
    func matches(_ mapping: PhotoMapping) -> Bool {
        id == mapping.id &&
            name == mapping.name &&
            destinationAlbumID == mapping.destinationAlbumID &&
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
