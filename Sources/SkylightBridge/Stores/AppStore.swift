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
    var isConnecting = false
    var isRefreshingSources = false
    var isSyncing = false
    var lastSyncAt: Date?
    var statusMessage = "Choose sources to begin."

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
        configureScheduler()
    }

    func saveConfiguration() {
        do {
            try persistence.saveConfiguration(configuration)
            configureScheduler()
            try applyLaunchAtLoginPreference()
            statusMessage = "Configuration saved."
        } catch {
            appendActivity(.init(
                level: .error,
                area: .system,
                message: "Could not save configuration: \(error.localizedDescription)"
            ))
        }
    }

    func refreshSources() async {
        guard !isRefreshingSources else { return }
        isRefreshingSources = true
        defer { isRefreshingSources = false }

        if photoLibrary.authorizationStatus() == .fullAccess {
            do {
                photoCollections = try photoLibrary.collections()
            } catch {
                recordSourceError(error, area: .photos)
            }
        }

        if remindersStore.authorizationStatus() == .fullAccess {
            do {
                reminderLists = try remindersStore.lists()
            } catch {
                recordSourceError(error, area: .reminders)
            }
        }

        statusMessage = "Sources refreshed."
    }

    func requestPhotosAccess() async {
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

    func requestNotesAccess() async {
        do {
            notesFolders = try await notesStore.folders()
            let configuredFolderIDs = Set([
                configuration.recipeSelection.folderID,
                configuration.mealSelection.folderID
            ].compactMap { $0 })
            for folderID in configuredFolderIDs {
                notesByFolderID[folderID] = try await notesStore.noteSummaries(inFolderID: folderID)
            }
            statusMessage = "Loaded \(notesFolders.count) Notes folders."
        } catch {
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
            statusMessage = "Connected to Skylight."
            appendActivity(.init(
                level: .success,
                area: .account,
                message: "Connected to Skylight and found \(connection.frames.count) frame(s). Credentials and OAuth tokens are stored in the macOS Keychain."
            ))
        } catch {
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
            let client = try await sessionManager.client(configuration: configuration.account)
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
            try persistence.saveConfiguration(configuration)
            statusMessage = "Connected to Skylight."
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
            saveConfiguration()
        } catch {
            recordSourceError(error, area: .account)
        }
    }

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard configuration.hasEnabledSync else {
            statusMessage = "No sources are enabled."
            appendActivity(.init(
                level: .warning,
                area: .system,
                message: "Nothing to sync. Add and enable at least one source mapping."
            ))
            return
        }

        do {
            try persistence.saveConfiguration(configuration)
            let client = try await sessionManager.client(configuration: configuration.account)
            let coordinator = SyncCoordinator.live(apiClient: client)
            let summary = try await coordinator.sync(configuration: configuration)
            record(summary.photos, area: .photos, dryRun: summary.dryRun)
            record(summary.reminders, area: .reminders, dryRun: summary.dryRun)
            record(summary.recipes, area: .recipes, dryRun: summary.dryRun)
            record(summary.meals, area: .meals, dryRun: summary.dryRun)
            lastSyncAt = .now
            statusMessage = summary.dryRun
                ? "Preview complete: \(summary.totalPlanned) change(s)."
                : "Sync complete: \(summary.totalApplied) change(s)."
            appendActivity(.init(
                level: summary.dryRun ? .info : .success,
                area: .system,
                message: statusMessage,
                isDryRun: summary.dryRun
            ))
        } catch {
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

    func deletePhotoMappings(at offsets: IndexSet) {
        configuration.photoMappings.remove(atOffsets: offsets)
        saveConfiguration()
    }

    func deleteReminderMappings(at offsets: IndexSet) {
        configuration.reminderMappings.remove(atOffsets: offsets)
        saveConfiguration()
    }

    private func configureScheduler() {
        scheduler.schedule(everyMinutes: max(configuration.syncIntervalMinutes, 10)) { [weak self] in
            await self?.syncNow()
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
            message: "\(count) change(s) \(verb).",
            isDryRun: dryRun
        ))
    }
}
