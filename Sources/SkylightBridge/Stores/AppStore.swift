import AppKit
import Foundation
import Observation
import SkylightBridgeShared

private enum AppStorePersistenceError: LocalizedError {
    case configurationRecoveryRequired(String)
    case activityRecoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case let .configurationRecoveryRequired(reason):
            "The existing configuration could not be read (\(reason)). It was not replaced. Restart after restoring access to the original file or Keychain key."
        case let .activityRecoveryRequired(reason):
            "The existing activity history could not be read (\(reason)). It was not replaced. Restart after restoring access to the original file or Keychain key."
        }
    }
}

@MainActor
protocol AppRemindersStoring {
    func authorizationStatus() -> AppleRemindersAuthorizationStatus
    func requestAccess() async throws -> Bool
    func lists() throws -> [AppleReminderListSnapshot]
    func reminders(in listID: String) async throws -> [AppleReminderSnapshot]
    func createList(named title: String) throws -> AppleReminderListSnapshot
    func deleteNewlyCreatedList(withID listID: String) throws
    func syncRemoveReminder(withID reminderID: String) async throws
}

extension AppleRemindersStore: AppRemindersStoring {}

struct SharedPreferenceFields: OptionSet, Sendable {
    let rawValue: UInt8

    static let selectedFrame = Self(rawValue: 1 << 0)
    static let dryRun = Self(rawValue: 1 << 1)
    static let syncInterval = Self(rawValue: 1 << 2)
}

struct SharedPreferenceMutationRecord: Sendable {
    var selectedFrame: (version: UInt64, value: String, modifiedAt: Date)?
    var dryRun: (version: UInt64, value: Bool, modifiedAt: Date)?
    var syncInterval: (version: UInt64, value: Int, modifiedAt: Date)?

    var latestVersion: UInt64 {
        max(
            selectedFrame?.version ?? 0,
            dryRun?.version ?? 0,
            syncInterval?.version ?? 0
        )
    }
}

struct PendingSharedPhotoChanges: Sendable {
    var additions: [UUID: Set<String>] = [:]
    var removals: [UUID: Set<String>] = [:]
    var portableMappings: [UUID: PhotoMapping] = [:]

    var isEmpty: Bool {
        additions.values.allSatisfy(\.isEmpty)
            && removals.values.allSatisfy(\.isEmpty)
            && portableMappings.isEmpty
    }

    var changeCount: Int {
        additions.values.reduce(0) { $0 + $1.count }
            + removals.values.reduce(0) { $0 + $1.count }
            + portableMappings.count
    }

    mutating func record(
        mappingID: UUID,
        additions addedAssetIDs: Set<String>,
        removals removedAssetIDs: Set<String>
    ) {
        additions[mappingID, default: []].formUnion(addedAssetIDs)
        additions[mappingID]?.subtract(removedAssetIDs)
        removals[mappingID, default: []].formUnion(removedAssetIDs)
        removals[mappingID]?.subtract(addedAssetIDs)
        removeEmptyEntries()
    }

    func applying(to assetIDs: Set<String>, mappingID: UUID) -> Set<String> {
        assetIDs
            .union(additions[mappingID] ?? [])
            .subtracting(removals[mappingID] ?? [])
    }

    mutating func recordPortableMapping(_ mapping: PhotoMapping) {
        portableMappings[mapping.id] = mapping
    }

    func applyingPortableFields(to mapping: PhotoMapping) -> PhotoMapping {
        guard let pending = portableMappings[mapping.id] else { return mapping }
        var result = mapping
        result.name = pending.name
        result.destinationAlbumTitle = pending.destinationAlbumTitle
        result.removalPolicy = pending.removalPolicy
        result.maximumLongEdge = pending.maximumLongEdge
        result.jpegQuality = pending.jpegQuality
        result.enabled = pending.enabled
        return result
    }

    mutating func acknowledge(_ published: PendingSharedPhotoChanges) {
        for (mappingID, assetIDs) in published.additions {
            additions[mappingID]?.subtract(assetIDs)
        }
        for (mappingID, assetIDs) in published.removals {
            removals[mappingID]?.subtract(assetIDs)
        }
        for (mappingID, mapping) in published.portableMappings
        where portableMappings[mappingID] == mapping {
            portableMappings.removeValue(forKey: mappingID)
        }
        removeEmptyEntries()
    }

    mutating func discard(mappingID: UUID) {
        additions.removeValue(forKey: mappingID)
        removals.removeValue(forKey: mappingID)
        portableMappings.removeValue(forKey: mappingID)
    }

    private mutating func removeEmptyEntries() {
        additions = additions.filter { !$0.value.isEmpty }
        removals = removals.filter { !$0.value.isEmpty }
    }
}

@MainActor
@Observable
final class AppStore {
    var selection: NavigationSection = .overview
    var configuration: AppConfiguration
    var activity: [ActivityEntry]
    var photoCollections: [ApplePhotoCollectionSnapshot] = []
    var reminderLists: [AppleReminderListSnapshot] = []
    var remindersByListID: [String: [AppleReminderSnapshot]] = [:]
    var notesFolders: [AppleNotesFolderSnapshot] = []
    var notesByFolderID: [String: [AppleNoteSummarySnapshot]] = [:]
    var skylightFrames: [SkylightResource<SkylightFrameAttributes>] = []
    var skylightDevices: [SkylightResource<SkylightDeviceAttributes>] = []
    var skylightAlbums: [SkylightResource<SkylightAlbumAttributes>] = []
    var skylightLists: [SkylightResource<SkylightListAttributes>] = []
    var skylightMealCategories: [SkylightResource<SkylightMealCategoryAttributes>] = []
   var skylightChoreCategories: [SkylightResource<SkylightCategoryAttributes>] = []
    var multiClientWarning: String?
    var photosAuthorizationStatus: ApplePhotosAuthorizationStatus = .notDetermined
    var remindersAuthorizationStatus: AppleRemindersAuthorizationStatus = .notDetermined
    var notesAccessGranted = false
    /// True when macOS recorded an explicit Automation denial for Notes. macOS
    /// never re-prompts after a denial, so the UI must route to System
    /// Settings instead of offering a request that silently does nothing.
    var notesAccessDenied = false
    var isConnecting = false
    /// Most recent sign-in or reconnect failure, shown inline on the Account
    /// screen. Cleared when a new attempt starts or succeeds.
    var connectionError: String?
    var isRefreshingSources = false
    var isSyncing = false
    var isSettingUpChoreLists = false
    var lastSyncAt: Date?
    /// True after a sync attempt fails, until the next attempt succeeds. Drives
    /// the menu bar's error state so background failures aren't invisible.
    var lastSyncFailed = false
    /// First-run welcome sheet.
    var isOnboardingPresented = false
    /// Milestone the donation sheet is currently thanking the user for.
    var donationPromptMilestone: Int?
    private var hasLoggedClassifierUnavailable = false
    @ObservationIgnored var hasLoggedSharediCloudSchemaDeploymentFailure = false

    private enum SupportDefaultsKey {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lifetimeAppliedChanges = "lifetimeAppliedChanges"
        static let donationPromptedMilestone = "donationPromptedMilestone"
        static let donationLastPromptDate = "donationLastPromptDate"
        static let donationDismissedPermanently = "donationDismissedPermanently"
        static let donationSupportOpenedDate = "donationSupportOpenedDate"
        static let isSkylightSignedOut = "isSkylightSignedOut"
    }
    var statusMessage = "Choose sources to begin."
    /// Non-nil when an existing configuration file failed authentication,
    /// decoding, or reading. The in-memory fallback stays read-only so startup
    /// recovery and background CloudKit work cannot overwrite the original.
    private(set) var configurationLoadError: String?
    /// Non-nil when the activity file failed authentication, decoding, or
    /// reading. Logging stays read-only so the unreadable file is preserved.
    private(set) var activityLoadError: String?
    var recoveryStatusMessage: String? {
        if let configurationLoadError {
            return "Configuration recovery is required: \(configurationLoadError)"
        }
        if let activityLoadError {
            return "Activity recovery is required: \(activityLoadError)"
        }
        return nil
    }
    private var hasStarted = false
    /// Newest-first, trimmed to `maximumActivityEntries` in memory as well as
    /// on disk; the Activity page renders every row it is handed.
    private static let maximumActivityEntries = 500
    var hasLoadedSharediCloudState = false

    private let persistence: ConfigurationStore
    @ObservationIgnored private let scheduler = BackgroundSyncScheduler()
    @ObservationIgnored let photoLibrary = ApplePhotoLibrary()
    @ObservationIgnored private let remindersStore: any AppRemindersStoring
    @ObservationIgnored private let notesStore = AppleNotesStore()
    @ObservationIgnored private let sessionManager: any SkylightSessionManaging
    @ObservationIgnored private let syncStateStore: SyncStateStore
    @ObservationIgnored let sharedPreferencesStore: any SharedPreferencesCloudStoring
    @ObservationIgnored let sharedPhotoMappingStore: any SharedPhotoMappingCloudStoring
    @ObservationIgnored var sharedCloudOperationInProgress = false
    @ObservationIgnored var sharedPreferencesOperationInProgress = false
    @ObservationIgnored var sharedPreferenceMutationVersion: UInt64 = 0
    @ObservationIgnored var sharedPreferenceMutations = SharedPreferenceMutationRecord()
    @ObservationIgnored var pendingSharedPhotoChanges = PendingSharedPhotoChanges()

    init(
        persistence: ConfigurationStore = ConfigurationStore(),
        sessionManager: any SkylightSessionManaging = SkylightSessionManager(),
        syncStateStore: SyncStateStore = SyncStateStore(),
        remindersStore: any AppRemindersStoring = AppleRemindersStore(),
        sharedPreferencesStore: any SharedPreferencesCloudStoring = CloudPreferencesStore(),
        sharedPhotoMappingStore: any SharedPhotoMappingCloudStoring = CloudPhotoMappingStore()
    ) {
        self.persistence = persistence
        self.sessionManager = sessionManager
        self.syncStateStore = syncStateStore
        self.remindersStore = remindersStore
        self.sharedPreferencesStore = sharedPreferencesStore
        self.sharedPhotoMappingStore = sharedPhotoMappingStore
        do {
            configuration = try persistence.loadConfiguration()
        } catch {
            configuration = .empty
            configurationLoadError = error.localizedDescription
        }
        do {
            activity = try persistence.loadActivity()
        } catch {
            activity = []
            activityLoadError = error.localizedDescription
        }
        photosAuthorizationStatus = photoLibrary.authorizationStatus()
        remindersAuthorizationStatus = remindersStore.authorizationStatus()
        if configurationLoadError == nil {
            configureScheduler()
        }
        if let recoveryStatusMessage {
            statusMessage = recoveryStatusMessage
        }
    }

    var isSkylightConnected: Bool {
        let frameID = configuration.account.frameID.trimmed
        return !frameID.isEmpty && skylightFrames.contains { $0.id == frameID }
    }

    private func timeZone(forFrameID frameID: String) -> TimeZone? {
        let frameID = frameID.trimmed
        guard let identifier = skylightFrames.first(where: { $0.id == frameID })?
            .attributes.timezone?.trimmed,
              !identifier.isEmpty else { return nil }
        return TimeZone(identifier: identifier)
    }

    /// Whether Sync Now can actually run. Mirrors the engine's gating copy so a
    /// hidden feature (Meals) never leaves an enabled button that only logs
    /// "nothing to sync".
    var canSyncNow: Bool {
        configurationLoadError == nil &&
            !isSyncing &&
            isSkylightConnected &&
            syncConfiguration.hasEnabledSync
    }

    /// Whether any engine-runnable source is enabled (hidden features forced
    /// off). Surfaces use this instead of the raw configuration flag so copy
    /// and controls agree with what a sync would actually do.
    var hasEnabledVisibleSync: Bool {
        syncConfiguration.hasEnabledSync
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        defer {
            if let recoveryStatusMessage {
                statusMessage = recoveryStatusMessage
            }
        }
        applyDockIconPreference()
        if !UserDefaults.standard.bool(forKey: SupportDefaultsKey.hasCompletedOnboarding) {
            isOnboardingPresented = true
        }
        guard configurationLoadError == nil else {
            // Keep recovery startup read-only. Even local source refreshes can
            // launch apps or prompt for access while the original file needs
            // attention.
            return
        }
        async let sources: Void = refreshSources()
        async let account: Void = restoreAccountConnection()
        _ = await (sources, account)
        await refreshSharediCloudState()
    }

    @discardableResult
    func saveConfiguration(
        triggerSync: Bool = false,
        sharedPreferenceFields: SharedPreferenceFields = [],
        publishSharedState: Bool = true
    ) -> Bool {
        // Photo display names for deselected assets are dead weight; the
        // sealed file has a hard size ceiling, so prune orphans before saving.
        for index in configuration.photoMappings.indices {
            let mapping = configuration.photoMappings[index]
            let pruned = mapping.selectedPhotoNames.filter { mapping.selectedAssetIDs.contains($0.key) }
            if pruned.count != mapping.selectedPhotoNames.count {
                configuration.photoMappings[index].selectedPhotoNames = pruned
            }
        }
        do {
            try persistConfiguration()
        } catch {
            statusMessage = "Could not save configuration: \(error.localizedDescription)"
            appendActivity(.init(
                level: .error,
                area: .system,
                message: "Could not save configuration: \(error.localizedDescription)"
            ))
            return false
        }
        if configurationLoadError == nil {
            configureScheduler()
        }
        if !sharedPreferenceFields.isEmpty {
            recordSharedPreferenceMutation(sharedPreferenceFields)
        }
        do {
            try applyLaunchAtLoginPreference()
            statusMessage = "Configuration saved."
        } catch {
            statusMessage = "Configuration saved, but the login setting could not be updated."
            appendActivity(.init(
                level: .warning,
                area: .system,
                message: "The configuration was saved, but the login setting could not be updated: \(error.localizedDescription)"
            ))
        }
        applyDockIconPreference()
        if publishSharedState, hasLoadedSharediCloudState {
            Task { await publishSharediCloudState() }
        }
        if triggerSync {
            autoSync()
        }
        return true
    }

    private func recordSharedPreferenceMutation(_ fields: SharedPreferenceFields) {
        sharedPreferenceMutationVersion &+= 1
        let version = sharedPreferenceMutationVersion
        let modifiedAt = Date.now
        if fields.contains(.selectedFrame) {
            sharedPreferenceMutations.selectedFrame = (
                version,
                configuration.account.frameID,
                modifiedAt
            )
        }
        if fields.contains(.dryRun) {
            sharedPreferenceMutations.dryRun = (
                version,
                configuration.dryRun,
                modifiedAt
            )
        }
        if fields.contains(.syncInterval) {
            sharedPreferenceMutations.syncInterval = (
                version,
                configuration.syncIntervalMinutes,
                modifiedAt
            )
        }
    }

    private func recordPersistedFrameChangeIfNeeded(from previousFrameID: String) {
        guard previousFrameID.trimmed != configuration.account.frameID.trimmed else { return }
        recordSharedPreferenceMutation([.selectedFrame])
        if hasLoadedSharediCloudState {
            Task { await publishSharediCloudState() }
        }
    }

    private func persistConfiguration() throws {
        if let configurationLoadError {
            throw AppStorePersistenceError.configurationRecoveryRequired(
                configurationLoadError
            )
        }
        try persistence.saveConfiguration(configuration)
    }

    /// The configuration a sync actually runs with. Hidden features are forced
    /// off here so a stale enabled flag cannot run a workflow that has no
    /// visible interface to inspect or stop it.
    private var syncConfiguration: AppConfiguration {
        var value = configuration
        if !FeatureFlags.mealSyncEnabled {
            value.mealSelection.enabled = false
        }
        return value
    }

    /// Runs a sync (a preview while Dry Run is on) right after a mapping is added,
    /// edited, or enabled, so the change lands in Activity without waiting for the
    /// background schedule. Skipped when nothing is connected or a sync is already
    /// in flight.
    private func autoSync() {
        guard syncConfiguration.hasEnabledSync, !isSyncing else { return }
        guard isSkylightConnected else {
            // The mapping was saved, but nothing can sync until sign-in; say so
            // instead of silently skipping the promised automatic sync.
            statusMessage = "Mapping saved. Sign in to Skylight to start syncing."
            appendActivity(.init(
                level: .warning,
                area: .account,
                message: "A mapping changed but no Skylight account is connected. Sign in to sync it."
            ))
            return
        }
        Task { await syncNow() }
    }

    func refreshSources() async {
        guard !isRefreshingSources else { return }
        isRefreshingSources = true
        defer { isRefreshingSources = false }

        photosAuthorizationStatus = photoLibrary.authorizationStatus()
        remindersAuthorizationStatus = remindersStore.authorizationStatus()
        refreshNotesAccessStatus()

        if photosAuthorizationStatus == .fullAccess {
            do {
                photoCollections = try photoLibrary.collections()
            } catch {
                recordSourceError(error, area: .photos)
            }
        } else {
            photoCollections = []
        }

        if remindersAuthorizationStatus == .fullAccess {
            do {
                reminderLists = try remindersStore.lists()
            } catch {
                recordSourceError(error, area: .reminders)
            }
        } else {
            reminderLists = []
        }

        // Reading folders sends an Apple Event, which launches Notes when it is
        // not running. At startup only do that when the permission check is
        // already definite, which means Notes is running anyway.
        if AppleNotesStore.authorizationStatus() == .granted {
            await loadNotesFolders()
        }

        completeSourceRefresh()
    }

    func completeSourceRefresh() {
        statusMessage = recoveryStatusMessage ?? "Sources refreshed."
    }

    /// Reads the Notes folder list whenever Automation access already exists.
    /// Without this the folders arrived only from `requestNotesAccess()`, so
    /// on later launches the folder picker was empty until the user pressed
    /// Refresh on the access row.
    func loadNotesFolders() async {
        guard notesAccessGranted else {
            notesFolders = []
            return
        }
        do {
            notesFolders = try await notesStore.folders()
        } catch {
            recordSourceError(error, area: .recipes)
        }
    }

    func requestPhotosAccess() async {
        let previousPolicy = prepareForAppleAccessPrompt()
        defer { restoreActivationPolicy(afterAppleAccessPrompt: previousPolicy) }
        defer { photosAuthorizationStatus = photoLibrary.authorizationStatus() }
        do {
            guard await photoLibrary.requestAccess() else {
                throw ApplePhotoLibraryError.accessDenied
            }
            photoCollections = try photoLibrary.collections()
            statusMessage = "Loaded \(photoCollections.count) Photos collections."
        } catch {
            recordSourceError(error, area: .photos)
            if photoLibrary.authorizationStatus() == .notDetermined {
                reportBlockedConsentPromptIfNeeded(area: .photos)
            }
        }
    }

    func requestRemindersAccess() async {
        let previousPolicy = prepareForAppleAccessPrompt()
        defer { restoreActivationPolicy(afterAppleAccessPrompt: previousPolicy) }
        defer { remindersAuthorizationStatus = remindersStore.authorizationStatus() }
        do {
            guard try await remindersStore.requestAccess() else {
                throw AppleRemindersStoreError.accessDenied
            }
            reminderLists = try remindersStore.lists()
            statusMessage = "Loaded \(reminderLists.count) Reminders lists."
        } catch {
            recordSourceError(error, area: .reminders)
            if remindersStore.authorizationStatus() == .notDetermined {
                reportBlockedConsentPromptIfNeeded(area: .reminders)
            }
        }
    }

    func loadReminders(in listID: String) async {
        guard !listID.isEmpty else { return }
        do {
            remindersByListID[listID] = try await remindersStore.reminders(in: listID)
        } catch {
            recordSourceError(error, area: .reminders)
        }
    }

    func createReminderList(named title: String) throws -> AppleReminderListSnapshot {
        let list = try remindersStore.createList(named: title)
        if let lists = try? remindersStore.lists() {
            reminderLists = lists
        }
        appendActivity(.init(
            level: .success,
            area: .reminders,
            message: "Created the Apple Reminders list “\(list.title)”."
        ))
        return list
    }

    /// Rolls back a list that the mapping editor just created when the mapping
    /// itself could not be persisted.
    func discardNewlyCreatedReminderList(withID listID: String) -> Bool {
        do {
            try remindersStore.deleteNewlyCreatedList(withID: listID)
            if let lists = try? remindersStore.lists() {
                reminderLists = lists
            }
            appendActivity(.init(
                level: .warning,
                area: .reminders,
                message: "Removed the new Apple Reminders list because its mapping could not be saved."
            ))
            return true
        } catch {
            recordSourceError(error, area: .reminders)
            return false
        }
    }

    /// Creates or reuses one Apple Reminders list for each person already
    /// enabled in Skylight's Chore Chart, plus the shared Up for Grabs list.
    /// Skylight is deliberately the source of setup truth, so the frame must
    /// be configured before this action is available.
    func setupChoreListsFromSkylight() async {
        guard !isSettingUpChoreLists, !isConnecting, !isSyncing else { return }
        guard configurationLoadError == nil else {
            statusMessage = "Restore the existing configuration before setting up chore lists."
            return
        }
        guard isSkylightConnected else {
            statusMessage = "Configure Skylight first, then set up chore lists."
            appendActivity(.init(
                level: .warning,
                area: .chores,
                message: "Chore setup needs a connected Skylight frame with its Chore Chart configured first."
            ))
            return
        }
        guard remindersAuthorizationStatus == .fullAccess else {
            statusMessage = "Allow Reminders access before setting up chore lists."
            return
        }
        isConnecting = true
        isSettingUpChoreLists = true
        defer {
            isConnecting = false
            isSettingUpChoreLists = false
        }

        let priorConfiguration = configuration
        let priorChoreCategories = skylightChoreCategories
        var createdListIDs: [String] = []
        do {
            let frameID = configuration.account.frameID.trimmed
            let client = try await sessionManager.client(configuration: configuration.account)
            let categories = try await client.listCategories(frameID: frameID)
                .filter { $0.attributes.selectedForChoreChart == true }
                .sorted {
                    ($0.attributes.label ?? "").localizedStandardCompare($1.attributes.label ?? "")
                        == .orderedAscending
                }
            guard !categories.isEmpty else {
                statusMessage = "Set up people in Skylight's Chore Chart first."
                appendActivity(.init(
                    level: .warning,
                    area: .chores,
                    message: "Skylight has no people selected for its Chore Chart. Configure the Chore Chart on Skylight, then try again."
                ))
                return
            }

            var availableLists = try remindersStore.lists()
                .filter(\.allowsContentModifications)
            var existingMapping = configuration.choreMappings.first {
                $0.frameID == frameID || ($0.frameID.isEmpty && configuration.choreMappings.count == 1)
            } ?? ChoreMapping()
            let oldLinks = Dictionary(uniqueKeysWithValues: existingMapping.memberLinks.map {
                ($0.memberKey, $0)
            })
            var links: [ChoreMemberLink] = categories.map { category in
                let trimmedLabel = category.attributes.label?.trimmed ?? ""
                let label = trimmedLabel.isEmpty ? "Person" : trimmedLabel
                return ChoreMemberLink(
                    memberKey: category.id,
                    memberLabel: label,
                    appleListTitle: oldLinks[category.id]?.appleListTitle ?? "\(label) Chores",
                    isEnabled: oldLinks[category.id]?.isEnabled ?? true
                )
            }
            links.append(ChoreMemberLink(
                memberKey: ChoreMemberLink.upForGrabsKey,
                memberLabel: "Up for Grabs",
                appleListTitle: oldLinks[ChoreMemberLink.upForGrabsKey]?.appleListTitle
                    ?? "Up for Grabs",
                isEnabled: oldLinks[ChoreMemberLink.upForGrabsKey]?.isEnabled ?? true
            ))

            for index in links.indices {
                let oldID = oldLinks[links[index].memberKey]?.appleListID
                let foundByID = oldID.flatMap { id in availableLists.first { $0.id == id } }
                let found = foundByID ?? availableLists.first {
                    $0.title.localizedCaseInsensitiveCompare(links[index].appleListTitle) == .orderedSame
                }
                let list: AppleReminderListSnapshot
                if let found {
                    list = found
                } else {
                    list = try remindersStore.createList(named: links[index].appleListTitle)
                    availableLists.append(list)
                    createdListIDs.append(list.id)
                }
                links[index].appleListID = list.id
            }

            existingMapping.frameID = frameID
            existingMapping.frameName = skylightFrames.first(where: { $0.id == frameID })?
                .attributes.name ?? "Skylight"
            existingMapping.memberLinks = links
            existingMapping.direction = .twoWay
            existingMapping.isEnabled = true
            if let index = configuration.choreMappings.firstIndex(where: { $0.id == existingMapping.id }) {
                configuration.choreMappings[index] = existingMapping
            } else {
                configuration.choreMappings.append(existingMapping)
            }
            reminderLists = try remindersStore.lists()
            skylightChoreCategories = categories
            guard saveConfiguration(triggerSync: true) else {
                configuration = priorConfiguration
                skylightChoreCategories = priorChoreCategories
                let cleanupFailures = rollbackNewlyCreatedReminderLists(createdListIDs)
                let message = cleanupFailures.isEmpty
                    ? "Chore setup could not be saved. The newly created Reminders lists were removed."
                    : "Chore setup could not be saved, and \(cleanupFailures.count) new Reminders list\(cleanupFailures.count == 1 ? "" : "s") could not be removed."
                appendActivity(.init(
                    level: cleanupFailures.isEmpty ? .warning : .error,
                    area: .chores,
                    message: message
                ))
                statusMessage = message
                return
            }
            let createdCount = createdListIDs.count
            let reused = links.count - createdCount
            statusMessage = "Chore lists are ready."
            appendActivity(.init(
                level: .success,
                area: .chores,
                message: "Chore setup created \(createdCount) Apple Reminders list\(createdCount == 1 ? "" : "s") and reused \(reused)."
            ))
        } catch {
            configuration = priorConfiguration
            skylightChoreCategories = priorChoreCategories
            let cleanupFailures = rollbackNewlyCreatedReminderLists(createdListIDs)
            recordSourceError(error, area: .chores)
            if !createdListIDs.isEmpty {
                let message = cleanupFailures.isEmpty
                    ? "Chore setup failed. The newly created Reminders lists were removed."
                    : "Chore setup failed, and \(cleanupFailures.count) new Reminders list\(cleanupFailures.count == 1 ? "" : "s") could not be removed."
                appendActivity(.init(
                    level: cleanupFailures.isEmpty ? .warning : .error,
                    area: .chores,
                    message: message
                ))
                statusMessage = message
            }
        }
    }

    /// Compensates only lists created by the current setup attempt. Existing
    /// lists remain untouched even when configuration persistence fails.
    private func rollbackNewlyCreatedReminderLists(_ listIDs: [String]) -> [String] {
        var failures: [String] = []
        for listID in listIDs.reversed() {
            do {
                try remindersStore.deleteNewlyCreatedList(withID: listID)
            } catch {
                failures.append(listID)
            }
        }
        if let currentLists = try? remindersStore.lists() {
            reminderLists = currentLists
        }
        return failures
    }

    /// Reads the Automation permission for Notes from TCC so the status rows
    /// reflect reality across launches instead of only after an in-session
    /// request. When the check is indeterminate (Notes not running), fall back
    /// to whether a request has ever succeeded on this Mac.
    private func refreshNotesAccessStatus() {
        switch AppleNotesStore.authorizationStatus() {
        case .granted:
            notesAccessGranted = true
            notesAccessDenied = false
        case .denied:
            notesAccessGranted = false
            notesAccessDenied = true
        case .notDetermined:
            notesAccessGranted = false
            notesAccessDenied = false
        case .unknown:
            notesAccessGranted = UserDefaults.standard.bool(forKey: Self.notesAccessEverGrantedKey)
            notesAccessDenied = false
        }
    }

    private static let notesAccessEverGrantedKey = "notesAccessEverGranted"

    func requestNotesAccess() async {
        let previousPolicy = prepareForAppleAccessPrompt()
        defer { restoreActivationPolicy(afterAppleAccessPrompt: previousPolicy) }
        do {
            try await launchNotesIfNeeded()
            try await notesStore.requestAccess()
            notesFolders = try await notesStore.folders()
            notesAccessGranted = true
            notesAccessDenied = false
            UserDefaults.standard.set(true, forKey: Self.notesAccessEverGrantedKey)
            let configuredFolderIDs = Set([
                configuration.recipeSelection.folderID,
                configuration.mealSelection.folderID
            ].compactMap { $0 })
            for folderID in configuredFolderIDs {
                notesByFolderID[folderID] = try await notesStore.noteSummaries(inFolderID: folderID)
            }
            statusMessage = "Loaded \(notesFolders.count) Notes folders."
        } catch {
            refreshNotesAccessStatus()
            notesAccessGranted = false
            recordSourceError(error, area: .recipes)
            switch AppleNotesStore.authorizationStatus() {
            case .notDetermined, .unknown:
                reportBlockedConsentPromptIfNeeded(area: .recipes)
            case .granted, .denied:
                break
            }
        }
    }

    /// The Apple Events permission API requires a live target process. Launch
    /// Notes without activating it so macOS can present Skylight Bridge's
    /// consent sheet while keeping the user's focus on the button they clicked.
    private func launchNotesIfNeeded() async throws {
        let bundleIdentifier = "com.apple.Notes"
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty else { return }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw AppleNotesStoreError.authorizationUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }

    /// Privacy consent sheets must be presented by a foreground application.
    /// When the Dock icon is hidden Skylight Bridge is an accessory app, and
    /// macOS 26 can return "not authorized" without registering or displaying
    /// a consent request. Temporarily use the regular activation policy while
    /// each system prompt is in flight, then restore the user's preference.
    private func prepareForAppleAccessPrompt() -> NSApplication.ActivationPolicy {
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        return previousPolicy
    }

    private func restoreActivationPolicy(
        afterAppleAccessPrompt previousPolicy: NSApplication.ActivationPolicy
    ) {
        guard NSApp.activationPolicy() != previousPolicy else { return }
        NSApp.setActivationPolicy(previousPolicy)
    }

    /// Clears a Notes folder link so the page returns to its unconfigured
    /// state. The notes themselves are untouched; only the bridge's record of
    /// which folder to read is removed.
    func removeNotesSelection(kind: NotesContentKind) {
        let title = (kind == .recipes
            ? configuration.recipeSelection.folderTitle
            : configuration.mealSelection.folderTitle) ?? "a folder"
        var replacement = NotesSelection(kind: kind)
        replacement.id = kind == .recipes
            ? configuration.recipeSelection.id
            : configuration.mealSelection.id
        if kind == .recipes {
            configuration.recipeSelection = replacement
        } else {
            configuration.mealSelection = replacement
        }
        saveConfiguration()
        statusMessage = "\(kind.label) sync is no longer linked to a Notes folder."
        appendActivity(.init(
            level: .info,
            area: kind == .recipes ? .recipes : .meals,
            message: "Unlinked \(kind.label.lowercased()) sync from the Apple Notes folder “\(title)”. No notes were changed."
        ))
    }

    func loadNotes(in folderID: String, area: IntegrationArea) async {
        guard !folderID.isEmpty else { return }
        do {
            notesByFolderID[folderID] = try await notesStore.noteSummaries(inFolderID: folderID)
        } catch {
            recordSourceError(error, area: area)
        }
    }

    func saveAccountCredentials(email: String, password: String) async {
        guard configurationLoadError == nil else { return }
        guard !email.trimmed.isEmpty, !password.isEmpty else {
            appendActivity(.init(
                level: .warning,
                area: .account,
                message: "Enter both a Skylight email and password."
            ))
            return
        }

        guard !isConnecting, !isSyncing else { return }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            let previousFrameID = configuration.account.frameID
            try await sessionManager.saveCredentials(email: email, password: password)
            // An explicit sign-in replaces the signed-out intent as soon as
            // credentials are stored. If the first connection is transiently
            // offline, startup can retry those valid credentials later.
            UserDefaults.standard.set(false, forKey: SupportDefaultsKey.isSkylightSignedOut)
            let connection = try await sessionManager.connect(configuration: configuration.account)
            skylightFrames = connection.frames
            prepareForFrameChange(
                from: configuration.account.frameID,
                to: connection.selectedFrameID
            )
            skylightDevices = connection.devices
            configuration.account.deviceID = connection.selectedDeviceID
            try persistConfiguration()
            recordPersistedFrameChangeIfNeeded(from: previousFrameID)
            configureScheduler()
            if try await refreshSkylightDestinations(using: connection.client) {
                try persistConfiguration()
            }
            statusMessage = "Connected to Skylight."
            appendActivity(.init(
                level: .success,
                area: .account,
                message: "Connected to Skylight and found \(countDescription(connection.frames.count, singular: "frame")). Credentials and OAuth tokens are stored in the macOS Keychain."
            ))
        } catch {
            connectionError = error.localizedDescription
            recordSourceError(error, area: .account)
        }
    }

    // MARK: - Onboarding and donation reminders

    func completeOnboarding(goToAccount: Bool) {
        UserDefaults.standard.set(true, forKey: SupportDefaultsKey.hasCompletedOnboarding)
        isOnboardingPresented = false
        if goToAccount {
            selection = .account
        }
    }

    var lifetimeAppliedChanges: Int {
        UserDefaults.standard.integer(forKey: SupportDefaultsKey.lifetimeAppliedChanges)
    }

    /// Accumulates the lifetime applied-change counter and raises the donation
    /// sheet when a new milestone is crossed and the policy's cooldowns allow.
    /// Called only after `isSyncing` has reset, so the policy's idle guard sees
    /// a truthful state.
    private func presentSupportPromptIfEarned(applying count: Int) {
        let defaults = UserDefaults.standard
        if count > 0 {
            defaults.set(lifetimeAppliedChanges + count, forKey: SupportDefaultsKey.lifetimeAppliedChanges)
        }
        guard donationPromptMilestone == nil, !isOnboardingPresented else { return }
        let context = SupportPromptPolicy.Context(
            isConnected: isSkylightConnected,
            isSyncing: isSyncing,
            lifetimeAppliedChanges: lifetimeAppliedChanges,
            promptedMilestone: defaults.integer(forKey: SupportDefaultsKey.donationPromptedMilestone),
            dismissedPermanently: defaults.bool(forKey: SupportDefaultsKey.donationDismissedPermanently),
            lastPromptDate: defaults.object(forKey: SupportDefaultsKey.donationLastPromptDate) as? Date,
            supportOpenedDate: defaults.object(forKey: SupportDefaultsKey.donationSupportOpenedDate) as? Date,
            now: .now
        )
        if let milestone = SupportPromptPolicy.milestoneToPrompt(context) {
            defaults.set(milestone, forKey: SupportDefaultsKey.donationPromptedMilestone)
            defaults.set(Date.now, forKey: SupportDefaultsKey.donationLastPromptDate)
            donationPromptMilestone = milestone
        }
    }

    func donationPromptSupport() {
        UserDefaults.standard.set(Date.now, forKey: SupportDefaultsKey.donationSupportOpenedDate)
        donationPromptMilestone = nil
        NSWorkspace.shared.open(DonationPromptView.donationURL)
    }

    func donationPromptLater() {
        donationPromptMilestone = nil
    }

    func donationPromptNever() {
        UserDefaults.standard.set(true, forKey: SupportDefaultsKey.donationDismissedPermanently)
        donationPromptMilestone = nil
    }

    func storedAccountEmail() async -> String {
        guard !isConnecting else { return "" }
        return (try? await sessionManager.storedEmail()) ?? ""
    }

    /// Disconnects the Skylight account: revokes the session (best effort) and
    /// deletes the stored email, password, and OAuth tokens from the Keychain.
    /// Mappings and sync history stay, so signing back in resumes where the
    /// account left off.
    func signOut() async {
        guard !isConnecting, !isSyncing else { return }
        isConnecting = true
        defer { isConnecting = false }
        UserDefaults.standard.set(true, forKey: SupportDefaultsKey.isSkylightSignedOut)
        // Clear connected state before token revocation yields. Reconnect and
        // scheduled-sync paths then remain inert for the entire sign-out.
        skylightFrames = []
        skylightDevices = []
        skylightAlbums = []
        skylightLists = []
        skylightMealCategories = []
        skylightChoreCategories = []
        var deletionError: (any Error)?
        do {
            try await sessionManager.signOut()
        } catch {
            deletionError = error
        }
        connectionError = deletionError?.localizedDescription
        multiClientWarning = nil
        // A stale failure banner must not outlive the account: signed out,
        // the menu bar should point at sign-in, not at a failed sync.
        lastSyncFailed = false
        statusMessage = deletionError == nil
            ? "Signed out of Skylight."
            : "Signed out, but macOS could not remove every Keychain item."
        appendActivity(.init(
            level: deletionError == nil ? .info : .warning,
            area: .account,
            message: deletionError == nil
                ? "Signed out of Skylight. The saved email, password, and session tokens were removed from the Keychain. Mappings were kept."
                : "The Skylight connection was closed, but macOS could not remove every Keychain item: \(deletionError?.localizedDescription ?? "Unknown error"). Mappings were kept."
        ))
    }

    func restoreAccountConnection() async {
        guard configurationLoadError == nil else { return }
        guard !isConnecting else { return }
        guard !UserDefaults.standard.bool(
            forKey: SupportDefaultsKey.isSkylightSignedOut
        ) else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            let previousFrameID = configuration.account.frameID
            let client = try await sessionManager.client(
                configuration: configuration.account,
                validateFrame: false
            )
            skylightFrames = try await client.listFrames()
            guard !skylightFrames.isEmpty else {
                throw SkylightSessionManagerError.noFrames
            }
            if !skylightFrames.contains(where: { $0.id == configuration.account.frameID }) {
                prepareForFrameChange(
                    from: configuration.account.frameID,
                    to: skylightFrames[0].id
                )
            }
            skylightDevices = try await client.listDevices(frameID: configuration.account.frameID)
            if !skylightDevices.contains(where: { $0.id == configuration.account.deviceID }) {
                configuration.account.deviceID = skylightDevices.first?.id ?? ""
            }
            _ = try await refreshSkylightDestinations(using: client)
            try persistConfiguration()
            recordPersistedFrameChangeIfNeeded(from: previousFrameID)
            statusMessage = "Connected to Skylight."
            connectionError = nil
            // A successful reconnect retires any earlier failure banner.
            lastSyncFailed = false
        } catch SkylightSessionManagerError.missingCredentials {
            // First launch is expected to have no saved account.
        } catch {
            recordSourceError(error, area: .account)
        }
    }

    @discardableResult
    func selectFrame(
        _ frameID: String,
        replacing previousFrameID: String? = nil,
        recordSharedPreferenceMutation: Bool = true
    ) async -> Bool {
        guard configurationLoadError == nil else { return false }
        guard !isConnecting, !isSyncing else { return false }
        isConnecting = true
        defer { isConnecting = false }
        let priorConfiguration = configuration
        let priorDevices = skylightDevices
        let priorAlbums = skylightAlbums
        let priorLists = skylightLists
        let priorMealCategories = skylightMealCategories
        let priorChoreCategories = skylightChoreCategories
        var committed = false
        defer {
            if !committed {
                configuration = priorConfiguration
                skylightDevices = priorDevices
                skylightAlbums = priorAlbums
                skylightLists = priorLists
                skylightMealCategories = priorMealCategories
                skylightChoreCategories = priorChoreCategories
            }
        }
        prepareForFrameChange(
            from: previousFrameID ?? configuration.account.frameID,
            to: frameID
        )
        do {
            let client = try await sessionManager.client(configuration: configuration.account)
            skylightDevices = try await client.listDevices(frameID: frameID)
            configuration.account.deviceID = skylightDevices.first?.id ?? ""
            _ = try await refreshSkylightDestinations(using: client)
            guard saveConfiguration(
                sharedPreferenceFields: recordSharedPreferenceMutation ? [.selectedFrame] : [],
                publishSharedState: recordSharedPreferenceMutation
            ) else { return false }
            committed = true
            return true
        } catch {
            recordSourceError(error, area: .account)
            return false
        }
    }

    /// Clears every identifier scoped to the previous frame before the new
    /// frame can sync. Titles and source selections remain, so each destination
    /// can be resolved or created safely on the selected frame.
    func prepareForFrameChange(from previousFrameID: String, to frameID: String) {
        let previous = previousFrameID.trimmed
        let replacement = frameID.trimmed
        configuration.account.frameID = replacement
        guard previous != replacement else { return }

        if !previous.isEmpty {
            for mapping in configuration.photoMappings {
                let key = FrameDestinationIdentity.key(
                    mappingID: mapping.id,
                    frameID: previous
                )
                if let albumID = mapping.destinationAlbumID?.trimmed,
                   !albumID.isEmpty {
                    configuration.photoDestinationAlbumIDsByFrame[key] = albumID
                } else if configuration.photoDestinationIntentIDsByFrame[key] != nil {
                    configuration.photoDestinationAlbumIDsByFrame.removeValue(forKey: key)
                }
            }
            for mapping in configuration.reminderMappings {
                let key = FrameDestinationIdentity.key(
                    mappingID: mapping.id,
                    frameID: previous
                )
                let listID = mapping.destinationListID.trimmed
                if !listID.isEmpty {
                    configuration.reminderDestinationListIDsByFrame[key] = listID
                } else if configuration.reminderDestinationIntentIDsByFrame[key] != nil {
                    configuration.reminderDestinationListIDsByFrame.removeValue(forKey: key)
                }
            }
            if let categoryID = configuration.recipeSelection.destinationCategoryID?.trimmed,
               !categoryID.isEmpty {
                configuration.recipeDestinationCategoryIDsByFrame[previous] = categoryID
            } else {
                configuration.recipeDestinationCategoryIDsByFrame.removeValue(forKey: previous)
            }
            if let categoryID = configuration.mealSelection.destinationCategoryID?.trimmed,
               !categoryID.isEmpty {
                configuration.mealDestinationCategoryIDsByFrame[previous] = categoryID
            } else {
                configuration.mealDestinationCategoryIDsByFrame.removeValue(forKey: previous)
            }
        }

        configuration.account.deviceID = ""
        for index in configuration.photoMappings.indices {
            let mappingID = configuration.photoMappings[index].id
            let key = FrameDestinationIdentity.key(
                mappingID: mappingID,
                frameID: replacement
            )
            configuration.photoMappings[index].destinationAlbumID =
                configuration.photoDestinationAlbumIDsByFrame[key]
        }
        for index in configuration.reminderMappings.indices {
            let mappingID = configuration.reminderMappings[index].id
            let key = FrameDestinationIdentity.key(
                mappingID: mappingID,
                frameID: replacement
            )
            configuration.reminderMappings[index].destinationListID =
                configuration.reminderDestinationListIDsByFrame[key] ?? ""
        }
        configuration.recipeSelection.destinationCategoryID =
            configuration.recipeDestinationCategoryIDsByFrame[replacement]
        configuration.mealSelection.destinationCategoryID =
            configuration.mealDestinationCategoryIDsByFrame[replacement]
        skylightDevices = []
        skylightAlbums = []
        skylightLists = []
        skylightMealCategories = []
        skylightChoreCategories = []
    }

    func syncNow() async {
        guard configurationLoadError == nil else { return }
        guard !isSyncing, !isConnecting else { return }
        isSyncing = true
        defer { isSyncing = false }

        let processLock: ProcessSyncLock
        do {
            processLock = try ProcessSyncLock.acquire()
        } catch {
            recordSourceError(error, area: .system)
            return
        }
        defer { withExtendedLifetime(processLock) {} }

        // A launch-time restore can fail on a transient network error, so a
        // scheduled sync first retries the connection. After sign-out the
        // retry finds no credentials and returns quietly, so the schedule
        // stops logging a missing-credentials error every interval.
        if !isSkylightConnected {
            await restoreAccountConnection()
        }
        guard isSkylightConnected else {
            statusMessage = "Sign in to Skylight to sync."
            return
        }

        let syncConfiguration = self.syncConfiguration
        let syncFrameID = syncConfiguration.account.frameID.trimmed
        let syncTimeZone = timeZone(forFrameID: syncFrameID)
        guard syncConfiguration.hasEnabledSync else {
            statusMessage = "No sources are enabled."
            appendActivity(.init(
                level: .warning,
                area: .system,
                message: "Nothing to sync. Add and enable at least one source mapping."
            ))
            return
        }

        if configuration.recipeSelection.enabled,
           (configuration.recipeSelection.destinationCategoryID ?? "").trimmed.isEmpty,
           !hasLoggedClassifierUnavailable,
           let reason = RecipeIntelligence.unavailabilityReason {
            hasLoggedClassifierUnavailable = true
            appendActivity(.init(
                level: .info,
                area: .recipes,
                message: "Automatic recipe categories fall back to the first Skylight category because \(reason)."
            ))
        }

        var appliedThisRun = 0
        do {
           try persistConfiguration()
           let client = try await sessionManager.client(configuration: configuration.account)
            // Notes automation reaches Apple Notes over Apple Events, which need
            // a live target process. A scheduled sync usually runs while Notes
            // is closed, so launch it first (without stealing focus); otherwise
            // the recipe and meal domains fail with "Connection is invalid".
            if syncConfiguration.recipeSelection.enabled || syncConfiguration.mealSelection.enabled {
                try? await launchNotesIfNeeded()
            }
            await importSharedSyncState()
            let coordinator = SyncCoordinator.live(
                apiClient: client,
                stateStore: syncStateStore,
                timeZone: syncTimeZone
            )
            let summary = try await coordinator.sync(configuration: syncConfiguration)
            if try await refreshSkylightDestinations(using: client, frameID: syncFrameID) {
                try persistConfiguration()
            }
            record(summary.photos, area: .photos, dryRun: summary.dryRun)
            record(summary.reminders, area: .reminders, dryRun: summary.dryRun)
            record(summary.chores, area: .chores, dryRun: summary.dryRun)
            record(summary.recipes, area: .recipes, dryRun: summary.dryRun)
            record(summary.meals, area: .meals, dryRun: summary.dryRun)
            lastSyncAt = .now
            lastSyncFailed = false
            if !summary.dryRun {
                appliedThisRun = summary.totalApplied
            }
            if !summary.dryRun {
                await publishSharedSyncState()
            }
            statusMessage = summary.dryRun
                ? "Preview complete: \(countDescription(summary.totalPlanned, singular: "change")) planned."
                : "Sync complete: \(countDescription(summary.totalApplied, singular: "change")) applied."
            appendActivity(.init(
                level: summary.dryRun ? .info : .success,
                area: .system,
                message: statusMessage,
                isDryRun: summary.dryRun
            ))
        } catch let error as DecodingError {
            lastSyncFailed = true
            statusMessage = "Sync failed: could not decode local data (\(error.fieldLevelDescription))."
            appendActivity(.init(
                level: .error,
                area: .system,
                message: statusMessage,
                isDryRun: configuration.dryRun
            ))
        } catch {
            lastSyncFailed = true
            statusMessage = "Sync failed: \(error.localizedDescription)"
            appendActivity(.init(
                level: .error,
                area: .system,
                message: statusMessage,
                isDryRun: configuration.dryRun
            ))
        }

        // Bookkeeping is done; reset the busy state before follow-up work so
        // the support prompt policy's idle guard sees a truthful store.
        if appliedThisRun > 0 {
            isSyncing = false
            presentSupportPromptIfEarned(applying: appliedThisRun)
        }
    }

    func appendActivity(_ entry: ActivityEntry) {
        guard activityLoadError == nil else { return }
        activity.insert(entry, at: 0)
        // Keep memory bounded to what is kept on disk (the newest 500).
        if activity.count > Self.maximumActivityEntries {
            activity.removeLast(activity.count - Self.maximumActivityEntries)
        }
        do {
            try persistence.saveActivity(activity)
        } catch {
            statusMessage = "Could not save activity: \(error.localizedDescription)"
        }
    }

    func clearActivity() {
        if let activityLoadError {
            statusMessage = AppStorePersistenceError.activityRecoveryRequired(
                activityLoadError
            ).localizedDescription
            return
        }
        do {
            try persistence.saveActivity([])
            activity.removeAll()
            statusMessage = "Activity cleared."
        } catch {
            statusMessage = "Could not clear activity: \(error.localizedDescription)"
        }
    }

    /// Runs a mapping teardown under the same guards as a sync: one at a time
    /// and holding the cross-process lock, so a scheduled sync cannot interleave
    /// its own load-modify-save of the sync state file. Returns false when the
    /// teardown did not complete and the mapping should be kept for a retry.
    private func runTeardown(
        _ area: IntegrationArea,
        _ body: () async throws -> Void
    ) async -> Bool {
        guard !isSyncing else {
            statusMessage = "A sync is running. Try again when it finishes."
            appendActivity(.init(
                level: .warning,
                area: area,
                message: "Remove link skipped while a sync is running; the mapping was kept."
            ))
            return false
        }
        isSyncing = true
        defer { isSyncing = false }

        let processLock: ProcessSyncLock
        do {
            processLock = try ProcessSyncLock.acquire()
        } catch {
            recordSourceError(error, area: .system)
            return false
        }
        defer { withExtendedLifetime(processLock) {} }

        do {
            try await body()
            return true
        } catch {
            recordSourceError(error, area: area)
            return false
        }
    }

    private func runRemoteTeardown(
        _ area: IntegrationArea,
        _ body: (SkylightAPIClient) async throws -> Void
    ) async -> Bool {
        guard !isConnecting else {
            statusMessage = "An account operation is running. Try again when it finishes."
            return false
        }
        isConnecting = true
        defer { isConnecting = false }
        return await runTeardown(area) {
            let client = try await sessionManager.client(configuration: configuration.account)
            try await body(client)
        }
    }

    /// Deletes a photo mapping and, when possible, removes the Skylight copies it
    /// created. Apple Photos is never touched, so the Skylight album is the only
    /// place the bridge put these photos. When Skylight cannot be reached, the
    /// mapping is kept so the cleanup can be retried instead of stranding the
    /// bridge-created copies untracked.
    func removePhotoMapping(_ mapping: PhotoMapping) async {
        guard !isConnecting, !isSyncing else {
            statusMessage = isSyncing
                ? "A sync is running. Try again when it finishes."
                : "An account operation is running. Try again when it finishes."
            return
        }
        let originalConfiguration = configuration
        guard let mappingIndex = configuration.photoMappings.firstIndex(where: {
            $0.id == mapping.id
        }) else { return }
        // Disable and persist before any destructive remote call. If cleanup
        // or the final save fails, the mapping remains visible and retryable,
        // but it cannot recreate content that teardown already removed.
        configuration.photoMappings[mappingIndex].enabled = false
        guard saveConfiguration() else {
            configuration = originalConfiguration
            return
        }
        if mapping.sourceKind == .selectedPhotos {
            pendingSharedPhotoChanges.recordPortableMapping(
                configuration.photoMappings[mappingIndex]
            )
        }
        let disabledConfiguration = configuration
        let frameID = configuration.account.frameID.trimmed
        var completed = true
        if !frameID.isEmpty {
            completed = await runRemoteTeardown(.photos) { client in
                let coordinator = SyncCoordinator.live(apiClient: client, stateStore: syncStateStore)
                let purge = try await coordinator.purgePhotoMapping(
                    mappingID: mapping.id,
                    frameID: frameID
                )
                if purge.photos > 0 || purge.albums > 0 {
                    var parts = [countDescription(purge.photos, singular: "photo")]
                    if purge.albums > 0 {
                        parts.append(countDescription(purge.albums, singular: "album"))
                    }
                    appendActivity(.init(
                        level: .success,
                        area: .photos,
                        message: "Removed \(parts.joined(separator: " and ")) from Skylight for “\(mapping.name)”."
                    ))
                }
            }
        }
        guard completed else { return }
        if mapping.sourceKind == .selectedPhotos {
            configuration.pendingPhotoMappingRetirements.removeAll { $0.id == mapping.id }
            configuration.pendingPhotoMappingRetirements.append(mapping)
        }
        configuration.photoMappings.removeAll { $0.id == mapping.id }
        configuration.retiredPhotoMappingIDs.insert(mapping.id)
        configuration.photoDestinationAlbumIDsByFrame =
            configuration.photoDestinationAlbumIDsByFrame.filter {
                !FrameDestinationIdentity.belongsToMapping($0.key, mappingID: mapping.id)
            }
        configuration.photoDestinationIntentIDsByFrame =
            configuration.photoDestinationIntentIDsByFrame.filter {
                !FrameDestinationIdentity.belongsToMapping($0.key, mappingID: mapping.id)
            }
        guard saveConfiguration() else {
            configuration = disabledConfiguration
            return
        }
        pendingSharedPhotoChanges.discard(mappingID: mapping.id)
        await retireSharedPhotoMapping(mapping)
    }

    /// Stores a locally generated display title without changing the selected
    /// Photos assets. The next sync publishes it as the linked Skylight photo's
    /// caption while keeping the local selection record cosmetic.
    func saveSelectedPhotoNames(_ names: [String: String], for mappingID: UUID) {
        guard !names.isEmpty,
              let index = configuration.photoMappings.firstIndex(where: { $0.id == mappingID }) else {
            return
        }

        let selectedAssetIDs = configuration.photoMappings[index].selectedAssetIDs
        let applicableNames = names.filter { selectedAssetIDs.contains($0.key) }
        guard !applicableNames.isEmpty else { return }

        configuration.photoMappings[index].selectedPhotoNames.merge(applicableNames) { _, new in new }
        saveConfiguration(triggerSync: true)
    }

    @discardableResult
    func saveReminderMapping(
        _ mapping: ReminderListMapping,
        destinationSelectionChanged: Bool,
        triggerSync: Bool = true
    ) -> Bool {
        let previousConfiguration = configuration
        let frameID = configuration.account.frameID.trimmed
        if !frameID.isEmpty {
            let key = FrameDestinationIdentity.key(mappingID: mapping.id, frameID: frameID)
            let destinationID = mapping.destinationListID.trimmed
            if destinationID.isEmpty {
                configuration.reminderDestinationListIDsByFrame.removeValue(forKey: key)
            } else {
                configuration.reminderDestinationListIDsByFrame[key] = destinationID
            }
            if destinationSelectionChanged {
                configuration.reminderDestinationIntentIDsByFrame[key] = UUID()
            }
        }
        if let index = configuration.reminderMappings.firstIndex(where: { $0.id == mapping.id }) {
            configuration.reminderMappings[index] = mapping
        } else {
            configuration.reminderMappings.append(mapping)
        }
        guard saveConfiguration(triggerSync: triggerSync) else {
            configuration = previousConfiguration
            return false
        }
        return true
    }

    /// Deletes a reminder mapping. Because the mapping can be two-way, the caller
    /// chooses whether to also remove the synced items from Skylight, from Apple
    /// Reminders, or from neither.
    func removeReminderMapping(
        _ mapping: ReminderListMapping,
        cleanup side: ReminderMappingCleanupSide
    ) async {
        guard !isConnecting, !isSyncing else {
            statusMessage = isSyncing
                ? "A sync is running. Try again when it finishes."
                : "An account operation is running. Try again when it finishes."
            return
        }
        let originalConfiguration = configuration
        guard let mappingIndex = configuration.reminderMappings.firstIndex(where: {
            $0.id == mapping.id
        }) else { return }
        configuration.reminderMappings[mappingIndex].enabled = false
        guard saveConfiguration() else {
            configuration = originalConfiguration
            return
        }
        let disabledConfiguration = configuration
        let frameID = configuration.account.frameID.trimmed
        var completed = true
        if side == .none {
            completed = await runTeardown(.reminders) {
                try await syncStateStore.removeReminderMappingRecords(mappingID: mapping.id)
            }
        } else if side == .appleReminders {
            completed = await runTeardown(.reminders) {
                var state = try await syncStateStore.load()
                let records = state.reminders
                    .filter { $0.mappingID == mapping.id }
                    .sorted { $0.appleReminderID < $1.appleReminderID }
                var removedIDs = Set<String>()
                for record in records {
                    if removedIDs.insert(record.appleReminderID).inserted {
                        do {
                            try await remindersStore.syncRemoveReminder(
                                withID: record.appleReminderID
                            )
                        } catch let error as AppleRemindersStoreError {
                            guard case .reminderNotFound = error else { throw error }
                        }
                    }
                    state.reminders.removeAll { $0.id == record.id }
                    try await syncStateStore.save(state)
                }
                state.reminderLists.removeAll { $0.mappingID == mapping.id }
                try await syncStateStore.save(state)
                if !removedIDs.isEmpty {
                    appendActivity(.init(
                        level: .success,
                        area: .reminders,
                        message: "Removed \(countDescription(removedIDs.count, singular: "item")) from Apple Reminders for “\(mapping.sourceListTitle)”."
                    ))
                }
            }
        } else if !frameID.isEmpty {
            completed = await runRemoteTeardown(.reminders) { client in
                let coordinator = SyncCoordinator.live(apiClient: client, stateStore: syncStateStore)
                let affected = try await coordinator.purgeReminderMapping(
                    mappingID: mapping.id,
                    frameID: frameID,
                    side: side
                )
                if affected > 0, side != .none {
                    let place = side == .skylight ? "Skylight" : "Apple Reminders"
                    appendActivity(.init(
                        level: .success,
                        area: .reminders,
                        message: "Removed \(countDescription(affected, singular: "item")) from \(place) for “\(mapping.sourceListTitle)”."
                    ))
                }
            }
        }
        guard completed else { return }
        configuration.reminderMappings.removeAll { $0.id == mapping.id }
        configuration.reminderDestinationListIDsByFrame =
            configuration.reminderDestinationListIDsByFrame.filter {
                !FrameDestinationIdentity.belongsToMapping($0.key, mappingID: mapping.id)
            }
        configuration.reminderDestinationIntentIDsByFrame =
            configuration.reminderDestinationIntentIDsByFrame.filter {
                !FrameDestinationIdentity.belongsToMapping($0.key, mappingID: mapping.id)
            }
        guard saveConfiguration() else {
            configuration = disabledConfiguration
            return
        }
    }

    /// Disables Chore Chart sync for a mapping and cleans up what it created.
    /// The mode chooses which side's chores to keep; the auto-created Apple
    /// chore lists are removed whenever the Apple side is cleared.
    func removeChoreMapping(_ mapping: ChoreMapping, mode: ChoreTeardownMode) async {
        guard !isConnecting, !isSyncing else {
            statusMessage = isSyncing
                ? "A sync is running. Try again when it finishes."
                : "An account operation is running. Try again when it finishes."
            return
        }
        let originalConfiguration = configuration
        guard let mappingIndex = configuration.choreMappings.firstIndex(where: {
            $0.id == mapping.id
        }) else { return }
        configuration.choreMappings[mappingIndex].isEnabled = false
        guard saveConfiguration() else {
            configuration = originalConfiguration
            return
        }
        let disabledConfiguration = configuration
        let frameID = mapping.frameID.trimmed.isEmpty
            ? configuration.account.frameID.trimmed
            : mapping.frameID.trimmed
        var completed = true
        if !frameID.isEmpty {
            completed = await runRemoteTeardown(.chores) { client in
                let coordinator = SyncCoordinator.live(apiClient: client, stateStore: syncStateStore)
                let result = try await coordinator.teardownChoreMapping(
                    mappingID: mapping.id,
                    frameID: frameID,
                    mode: mode,
                    appleListIDs: choreListIDs(for: mapping)
                )
                recordChoreTeardown(result)
            }
        }
        guard completed else { return }
        configuration.choreMappings.removeAll { $0.id == mapping.id }
        guard saveConfiguration() else {
            configuration = disabledConfiguration
            return
        }
    }

    /// Resolves the Apple Reminders list identifiers a chore mapping owns, using
    /// each member link's stored list id and falling back to a title match for
    /// links saved before the id was recorded.
    private func choreListIDs(for mapping: ChoreMapping) -> [String] {
        let lists = (try? remindersStore.lists()) ?? []
        var ids: [String] = []
        for link in mapping.memberLinks {
            let configuredID = link.appleListID?.trimmed ?? ""
            if !configuredID.isEmpty, lists.contains(where: { $0.id == configuredID }) {
                ids.append(configuredID)
            } else if let match = lists.first(where: {
                $0.title.localizedCaseInsensitiveCompare(link.appleListTitle) == .orderedSame
            }) {
                ids.append(match.id)
            }
        }
        return ids
    }

    private func recordChoreTeardown(_ result: ChoreTeardownResult) {
        var parts: [String] = []
        if result.skylightItemsRemoved > 0 {
            parts.append("\(countDescription(result.skylightItemsRemoved, singular: "chore")) from Skylight")
        }
        if result.appleItemsRemoved > 0 {
            parts.append("\(countDescription(result.appleItemsRemoved, singular: "chore")) from Apple Reminders")
        }
        if result.listsRemoved > 0 {
            parts.append("\(countDescription(result.listsRemoved, singular: "empty list")) from Apple Reminders")
        }
        guard !parts.isEmpty else { return }
        appendActivity(.init(
            level: .success,
            area: .chores,
            message: "Chore sync disabled. Removed \(parts.joined(separator: ", "))."
        ))
    }

    func refreshSkylightDestinations() async {
        guard configurationLoadError == nil else { return }
        guard !isConnecting, !isSyncing else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let client = try await sessionManager.client(configuration: configuration.account)
            if try await refreshSkylightDestinations(using: client) {
                try persistConfiguration()
            }
        } catch SkylightSessionManagerError.missingCredentials {
            // Account setup is optional until the first sync.
        } catch {
            recordSourceError(error, area: .account)
        }
    }

    @ObservationIgnored private var scheduledIntervalMinutes: Int?

    private func configureScheduler() {
        // Every mapping edit autosaves, and each schedule call restarts the
        // background countdown; reschedule only when the interval changed so
        // edits cannot postpone the automatic sync indefinitely.
        let minutes = max(configuration.syncIntervalMinutes, 10)
        guard scheduledIntervalMinutes != minutes else { return }
        scheduledIntervalMinutes = minutes
        scheduler.schedule(everyMinutes: minutes) { [weak self] in
            await self?.syncNow()
        }
    }

    private func refreshSkylightDestinations(
        using client: SkylightAPIClient,
        frameID requestedFrameID: String? = nil
    ) async throws -> Bool {
        let frameID = (requestedFrameID ?? configuration.account.frameID).trimmed
        guard !frameID.isEmpty else {
            skylightAlbums = []
            skylightLists = []
            skylightMealCategories = []
            skylightChoreCategories = []
            return false
        }
        async let albums = client.listAlbums(frameID: frameID)
        async let lists = client.listLists(frameID: frameID).data
        async let mealCategories = client.listMealCategories(frameID: frameID)
        async let choreCategories = client.listCategories(frameID: frameID)
        skylightAlbums = try await albums.sorted {
            ($0.attributes.title ?? "").localizedStandardCompare($1.attributes.title ?? "") == .orderedAscending
        }
        skylightLists = try await lists.sorted {
            ($0.attributes.label ?? "").localizedStandardCompare($1.attributes.label ?? "") == .orderedAscending
        }
        skylightMealCategories = (try? await mealCategories)?.sorted {
            ($0.attributes.label ?? "").localizedStandardCompare($1.attributes.label ?? "") == .orderedAscending
        } ?? []
        skylightChoreCategories = (try? await choreCategories)?.filter {
            $0.attributes.selectedForChoreChart == true
        }.sorted {
            ($0.attributes.label ?? "").localizedStandardCompare($1.attributes.label ?? "")
                == .orderedAscending
        } ?? []
        let state = try? await syncStateStore.load()
        return hydrateUniqueDestinationIDs(from: state)
    }

    /// Restores a destination from exact frame-scoped sync state before using
    /// a title match. A title can identify a replacement album or list after
    /// the original destination was renamed, so it is only a fallback.
    @discardableResult
    func hydrateUniqueDestinationIDs(from state: SyncState?) -> Bool {
        let frameID = configuration.account.frameID.trimmed
        var changed = false
        for index in configuration.photoMappings.indices {
            let mapping = configuration.photoMappings[index]
            if let configuredID = mapping.destinationAlbumID?.trimmed,
               !configuredID.isEmpty,
               skylightAlbums.contains(where: { $0.id == configuredID }) {
                continue
            }
            if mapping.destinationAlbumID?.isEmpty == false {
                configuration.photoMappings[index].destinationAlbumID = nil
                changed = true
            }
            let key = FrameDestinationIdentity.key(mappingID: mapping.id, frameID: frameID)
            let intentID = configuration.photoDestinationIntentIDsByFrame[key]
            let stateDestinationIDs = (state?.photoDestinations
                .filter {
                    $0.mappingID == mapping.id &&
                        $0.frameID == frameID &&
                        (intentID == nil || $0.destinationIntentID == intentID)
                }
                .map(\.albumID) ?? []) + (state?.photos
                .filter {
                    intentID == nil && $0.mappingID == mapping.id && $0.frameID == frameID
                }
                .sorted { $0.lastSyncedAt > $1.lastSyncedAt }
                .flatMap { [$0.destinationAlbumID] + $0.skylightAlbumIDs.sorted() } ?? [])
            if let exact = stateDestinationIDs.first(where: { candidate in
                skylightAlbums.contains { $0.id == candidate }
            }) {
                configuration.photoMappings[index].destinationAlbumID = exact
                changed = true
                continue
            }
            // An intent with no live acknowledged record means the user chose
            // “New”. A same-title destination belongs to the older intent and
            // must not silently replace that choice.
            if intentID != nil { continue }
            let matches = skylightAlbums.filter {
                $0.attributes.title?.localizedCaseInsensitiveCompare(
                    mapping.destinationAlbumTitle
                ) == .orderedSame
            }
            if matches.count == 1 {
                configuration.photoMappings[index].destinationAlbumID = matches[0].id
                changed = true
            }
        }
        for index in configuration.reminderMappings.indices {
            let mapping = configuration.reminderMappings[index]
            let configuredID = mapping.destinationListID.trimmed
            if !configuredID.isEmpty,
               skylightLists.contains(where: { $0.id == configuredID }) {
                continue
            }
            if !mapping.destinationListID.isEmpty {
                configuration.reminderMappings[index].destinationListID = ""
                changed = true
            }
            let key = FrameDestinationIdentity.key(mappingID: mapping.id, frameID: frameID)
            let intentID = configuration.reminderDestinationIntentIDsByFrame[key]
            let stateDestinationIDs = (state?.reminderLists
                .filter {
                    $0.mappingID == mapping.id &&
                        $0.frameID == frameID &&
                        (intentID == nil || $0.destinationIntentID == intentID)
                }
                .map(\.skylightListID) ?? []) + (state?.reminders
                .filter {
                    intentID == nil && $0.mappingID == mapping.id && $0.frameID == frameID
                }
                .sorted { $0.lastSkylightModifiedAt > $1.lastSkylightModifiedAt }
                .map(\.skylightListID) ?? [])
            if let exact = stateDestinationIDs.first(where: { candidate in
                skylightLists.contains { $0.id == candidate }
            }) {
                configuration.reminderMappings[index].destinationListID = exact
                changed = true
                continue
            }
            if intentID != nil { continue }
            let matches = skylightLists.filter {
                $0.attributes.label?.localizedCaseInsensitiveCompare(
                    mapping.destinationListTitle
                ) == .orderedSame
            }
            if matches.count == 1 {
                configuration.reminderMappings[index].destinationListID = matches[0].id
                changed = true
            }
        }
        return changed
    }

    /// Removes a durable CloudKit retirement only after the disabled mapping
    /// was saved remotely and the smaller pending configuration was persisted.
    func completePhotoMappingRetirement(_ mappingID: UUID) {
        let previous = configuration.pendingPhotoMappingRetirements
        configuration.pendingPhotoMappingRetirements.removeAll { $0.id == mappingID }
        do {
            try persistConfiguration()
        } catch {
            configuration.pendingPhotoMappingRetirements = previous
            appendActivity(.init(
                level: .warning,
                area: .photos,
                message: "The disabled iCloud mapping was saved, but its local retry marker could not be cleared: \(error.localizedDescription)"
            ))
        }
    }

    /// Hiding the Dock icon switches the app to the accessory activation
    /// policy: menu bar extra and windows keep working, but the app leaves the
    /// Dock and the Command-Tab switcher.
    private func applyDockIconPreference() {
        // Mirror for AppDelegate, which needs the value before config loads.
        UserDefaults.standard.set(configuration.hideDockIcon, forKey: "hideDockIcon")
        guard let application = NSApp else { return }
        let policy: NSApplication.ActivationPolicy = configuration.hideDockIcon ? .accessory : .regular
        guard application.activationPolicy() != policy else { return }
        application.setActivationPolicy(policy)
        if policy == .regular {
            application.activate(ignoringOtherApps: true)
        }
    }

    private func applyLaunchAtLoginPreference() throws {
        guard LaunchAtLoginService.isEnabled != configuration.launchAtLogin else { return }
        try LaunchAtLoginService.setEnabled(configuration.launchAtLogin)
    }

    /// A permission request that ends with no recorded decision usually means
    /// macOS refused to present the consent prompt at all. When the boot
    /// configuration explains that refusal, replace the generic error with
    /// the actionable diagnosis.
    private func reportBlockedConsentPromptIfNeeded(area: IntegrationArea) {
        guard let explanation = SystemSecurityDiagnostics.blockedConsentPromptExplanation() else {
            return
        }
        statusMessage = explanation
        appendActivity(.init(level: .warning, area: area, message: explanation))
    }

    private func recordSourceError(_ error: any Error, area: IntegrationArea) {
        let message = error.localizedDescription
        statusMessage = message
        appendActivity(.init(level: .error, area: area, message: message))
    }

    private func record(_ summary: SyncDomainSummary, area: IntegrationArea, dryRun: Bool) {
        for warning in summary.warnings {
            appendActivity(.init(
                level: .warning,
                area: area,
                message: warning,
                isDryRun: dryRun
            ))
        }
        guard summary.planned > 0 else { return }
        let verb = dryRun ? "planned" : "applied"
        let count = dryRun ? summary.planned : summary.applied
        appendActivity(.init(
            level: dryRun ? .info : .success,
            area: area,
            message: "\(countDescription(count, singular: "change")) \(verb).",
            isDryRun: dryRun
        ))
    }

    private func countDescription(_ count: Int, singular: String) -> String {
        "\(count) \(count == 1 ? singular : singular + "s")"
    }
}
