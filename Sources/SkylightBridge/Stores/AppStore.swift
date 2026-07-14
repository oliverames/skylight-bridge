import AppKit
import Foundation
import Observation

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
    var photosAuthorizationStatus: ApplePhotosAuthorizationStatus = .notDetermined
    var remindersAuthorizationStatus: AppleRemindersAuthorizationStatus = .notDetermined
    var notesAccessGranted = false
    var isConnecting = false
    /// Most recent sign-in or reconnect failure, shown inline on the Account
    /// screen. Cleared when a new attempt starts or succeeds.
    var connectionError: String?
    var isRefreshingSources = false
    var isSyncing = false
    var lastSyncAt: Date?
    /// True after a sync attempt fails, until the next attempt succeeds. Drives
    /// the menu bar's error state so background failures aren't invisible.
    var lastSyncFailed = false
    private var hasLoggedClassifierUnavailable = false
    var statusMessage = "Choose sources to begin."
    private var hasStarted = false

    private let persistence: ConfigurationStore
    @ObservationIgnored private let scheduler = BackgroundSyncScheduler()
    @ObservationIgnored private let photoLibrary = ApplePhotoLibrary()
    @ObservationIgnored private let remindersStore = AppleRemindersStore()
    @ObservationIgnored private let notesStore = AppleNotesStore()
    @ObservationIgnored private let sessionManager = SkylightSessionManager()

    init(persistence: ConfigurationStore = ConfigurationStore()) {
        self.persistence = persistence
        configuration = (try? persistence.loadConfiguration()) ?? .empty
        activity = (try? persistence.loadActivity()) ?? []
        photosAuthorizationStatus = photoLibrary.authorizationStatus()
        remindersAuthorizationStatus = remindersStore.authorizationStatus()
        configureScheduler()
    }

    var isSkylightConnected: Bool {
        !configuration.account.frameID.isEmpty && !skylightFrames.isEmpty
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        applyDockIconPreference()
        async let sources: Void = refreshSources()
        async let account: Void = restoreAccountConnection()
        _ = await (sources, account)
    }

    func saveConfiguration(triggerSync: Bool = false) {
        do {
            try persistence.saveConfiguration(configuration)
            configureScheduler()
            try applyLaunchAtLoginPreference()
            applyDockIconPreference()
            statusMessage = "Configuration saved."
        } catch {
            appendActivity(.init(
                level: .error,
                area: .system,
                message: "Could not save configuration: \(error.localizedDescription)"
            ))
            return
        }
        if triggerSync {
            autoSync()
        }
    }

    /// Runs a sync (a preview while Dry Run is on) right after a mapping is added,
    /// edited, or enabled, so the change lands in Activity without waiting for the
    /// background schedule. Skipped when nothing is connected or a sync is already
    /// in flight.
    private func autoSync() {
        guard configuration.hasEnabledSync, !isSyncing else { return }
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

        statusMessage = "Sources refreshed."
    }

    func requestPhotosAccess() async {
        defer { photosAuthorizationStatus = photoLibrary.authorizationStatus() }
        do {
            guard await photoLibrary.requestAccess() else {
                throw ApplePhotoLibraryError.accessDenied
            }
            photoCollections = try photoLibrary.collections()
            statusMessage = "Loaded \(photoCollections.count) Photos collections."
        } catch {
            recordSourceError(error, area: .photos)
        }
    }

    func requestRemindersAccess() async {
        defer { remindersAuthorizationStatus = remindersStore.authorizationStatus() }
        do {
            guard try await remindersStore.requestAccess() else {
                throw AppleRemindersStoreError.accessDenied
            }
            reminderLists = try remindersStore.lists()
            statusMessage = "Loaded \(reminderLists.count) Reminders lists."
        } catch {
            recordSourceError(error, area: .reminders)
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

    /// Reads the Automation permission for Notes from TCC so the status rows
    /// reflect reality across launches instead of only after an in-session
    /// request. When the check is indeterminate (Notes not running), fall back
    /// to whether a request has ever succeeded on this Mac.
    private func refreshNotesAccessStatus() {
        switch AppleNotesStore.authorizationStatus() {
        case .granted:
            notesAccessGranted = true
        case .denied, .notDetermined:
            notesAccessGranted = false
        case .unknown:
            notesAccessGranted = UserDefaults.standard.bool(forKey: Self.notesAccessEverGrantedKey)
        }
    }

    private static let notesAccessEverGrantedKey = "notesAccessEverGranted"

    func requestNotesAccess() async {
        do {
            notesFolders = try await notesStore.folders()
            notesAccessGranted = true
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
            notesAccessGranted = false
            recordSourceError(error, area: .recipes)
        }
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
        guard !email.trimmed.isEmpty, !password.isEmpty else {
            appendActivity(.init(
                level: .warning,
                area: .account,
                message: "Enter both a Skylight email and password."
            ))
            return
        }

        guard !isConnecting else { return }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            try await sessionManager.saveCredentials(email: email, password: password)
            let connection = try await sessionManager.connect(configuration: configuration.account)
            skylightFrames = connection.frames
            skylightDevices = connection.devices
            configuration.account.frameID = connection.selectedFrameID
            configuration.account.deviceID = connection.selectedDeviceID
            try persistence.saveConfiguration(configuration)
            configureScheduler()
            try await refreshSkylightDestinations(using: connection.client)
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

    func storedAccountEmail() async -> String {
        (try? await sessionManager.storedEmail()) ?? ""
    }

    func restoreAccountConnection() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            let client = try await sessionManager.client(
                configuration: configuration.account,
                validateFrame: false
            )
            skylightFrames = try await client.listFrames()
            guard !skylightFrames.isEmpty else {
                throw SkylightSessionManagerError.noFrames
            }
            if !skylightFrames.contains(where: { $0.id == configuration.account.frameID }) {
                configuration.account.frameID = skylightFrames[0].id
            }
            skylightDevices = try await client.listDevices(frameID: configuration.account.frameID)
            if !skylightDevices.contains(where: { $0.id == configuration.account.deviceID }) {
                configuration.account.deviceID = skylightDevices.first?.id ?? ""
            }
            try await refreshSkylightDestinations(using: client)
            try persistence.saveConfiguration(configuration)
            statusMessage = "Connected to Skylight."
            connectionError = nil
        } catch SkylightSessionManagerError.missingCredentials {
            // First launch is expected to have no saved account.
        } catch {
            recordSourceError(error, area: .account)
        }
    }

    func selectFrame(_ frameID: String) async {
        configuration.account.frameID = frameID
        configuration.account.deviceID = ""
        do {
            let client = try await sessionManager.client(configuration: configuration.account)
            skylightDevices = try await client.listDevices(frameID: frameID)
            configuration.account.deviceID = skylightDevices.first?.id ?? ""
            try await refreshSkylightDestinations(using: client)
            saveConfiguration()
        } catch {
            recordSourceError(error, area: .account)
        }
    }

    func syncNow() async {
        guard !isSyncing else { return }
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

        guard configuration.hasEnabledSync else {
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

        do {
            try persistence.saveConfiguration(configuration)
            let client = try await sessionManager.client(configuration: configuration.account)
            let coordinator = SyncCoordinator.live(apiClient: client)
            let summary = try await coordinator.sync(configuration: configuration)
            try await refreshSkylightDestinations(using: client)
            record(summary.photos, area: .photos, dryRun: summary.dryRun)
            record(summary.reminders, area: .reminders, dryRun: summary.dryRun)
            record(summary.recipes, area: .recipes, dryRun: summary.dryRun)
            record(summary.meals, area: .meals, dryRun: summary.dryRun)
            lastSyncAt = .now
            lastSyncFailed = false
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
    }

    func appendActivity(_ entry: ActivityEntry) {
        activity.insert(entry, at: 0)
        try? persistence.saveActivity(activity)
    }

    func clearActivity() {
        activity.removeAll()
        do {
            try persistence.saveActivity(activity)
            statusMessage = "Activity cleared."
        } catch {
            recordSourceError(error, area: .system)
        }
    }

    /// Deletes a photo mapping and, when possible, removes the Skylight copies it
    /// created. Apple Photos is never touched, so the Skylight album is the only
    /// place the bridge put these photos.
    func removePhotoMapping(_ mapping: PhotoMapping) async {
        let frameID = configuration.account.frameID.trimmed
        if !frameID.isEmpty, isSkylightConnected {
            do {
                let client = try await sessionManager.client(configuration: configuration.account)
                let coordinator = SyncCoordinator.live(apiClient: client)
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
            } catch {
                recordSourceError(error, area: .photos)
            }
        }
        configuration.photoMappings.removeAll { $0.id == mapping.id }
        saveConfiguration()
    }

    /// Deletes a reminder mapping. Because the mapping can be two-way, the caller
    /// chooses whether to also remove the synced items from Skylight, from Apple
    /// Reminders, or from neither.
    func removeReminderMapping(
        _ mapping: ReminderListMapping,
        cleanup side: ReminderMappingCleanupSide
    ) async {
        let frameID = configuration.account.frameID.trimmed
        if !frameID.isEmpty, isSkylightConnected {
            do {
                let client = try await sessionManager.client(configuration: configuration.account)
                let coordinator = SyncCoordinator.live(apiClient: client)
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
            } catch {
                recordSourceError(error, area: .reminders)
            }
        }
        configuration.reminderMappings.removeAll { $0.id == mapping.id }
        saveConfiguration()
    }

    func refreshSkylightDestinations() async {
        do {
            let client = try await sessionManager.client(configuration: configuration.account)
            try await refreshSkylightDestinations(using: client)
        } catch SkylightSessionManagerError.missingCredentials {
            // Account setup is optional until the first sync.
        } catch {
            recordSourceError(error, area: .account)
        }
    }

    private func configureScheduler() {
        scheduler.schedule(everyMinutes: max(configuration.syncIntervalMinutes, 10)) { [weak self] in
            await self?.syncNow()
        }
    }

    private func refreshSkylightDestinations(using client: SkylightAPIClient) async throws {
        let frameID = configuration.account.frameID.trimmed
        guard !frameID.isEmpty else {
            skylightAlbums = []
            skylightLists = []
            skylightMealCategories = []
            return
        }
        async let albums = client.listAlbums(frameID: frameID)
        async let lists = client.listLists(frameID: frameID).data
        async let mealCategories = client.listMealCategories(frameID: frameID)
        skylightAlbums = try await albums.sorted {
            ($0.attributes.title ?? "").localizedStandardCompare($1.attributes.title ?? "") == .orderedAscending
        }
        skylightLists = try await lists.sorted {
            ($0.attributes.label ?? "").localizedStandardCompare($1.attributes.label ?? "") == .orderedAscending
        }
        skylightMealCategories = (try? await mealCategories)?.sorted {
            ($0.attributes.label ?? "").localizedStandardCompare($1.attributes.label ?? "") == .orderedAscending
        } ?? []
        hydrateUniqueDestinationIDs()
    }

    private func hydrateUniqueDestinationIDs() {
        var changed = false
        for index in configuration.photoMappings.indices
        where configuration.photoMappings[index].destinationAlbumID?.isEmpty != false {
            let title = configuration.photoMappings[index].destinationAlbumTitle
            let matches = skylightAlbums.filter {
                $0.attributes.title?.localizedCaseInsensitiveCompare(title) == .orderedSame
            }
            if matches.count == 1 {
                configuration.photoMappings[index].destinationAlbumID = matches[0].id
                changed = true
            }
        }
        for index in configuration.reminderMappings.indices
        where configuration.reminderMappings[index].destinationListID.isEmpty {
            let title = configuration.reminderMappings[index].destinationListTitle
            let matches = skylightLists.filter {
                $0.attributes.label?.localizedCaseInsensitiveCompare(title) == .orderedSame
            }
            if matches.count == 1 {
                configuration.reminderMappings[index].destinationListID = matches[0].id
                changed = true
            }
        }
        if changed {
            try? persistence.saveConfiguration(configuration)
        }
    }

    /// Hiding the Dock icon switches the app to the accessory activation
    /// policy: menu bar extra and windows keep working, but the app leaves the
    /// Dock and the Command-Tab switcher.
    private func applyDockIconPreference() {
        // Mirror for AppDelegate, which needs the value before config loads.
        UserDefaults.standard.set(configuration.hideDockIcon, forKey: "hideDockIcon")
        let policy: NSApplication.ActivationPolicy = configuration.hideDockIcon ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyLaunchAtLoginPreference() throws {
        guard LaunchAtLoginService.isEnabled != configuration.launchAtLogin else { return }
        try LaunchAtLoginService.setEnabled(configuration.launchAtLogin)
    }

    private func recordSourceError(_ error: any Error, area: IntegrationArea) {
        let message = error.localizedDescription
        statusMessage = message
        appendActivity(.init(level: .error, area: area, message: message))
    }

    private func record(_ summary: SyncDomainSummary, area: IntegrationArea, dryRun: Bool) {
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
