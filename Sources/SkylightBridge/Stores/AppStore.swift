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
    }
    var statusMessage = "Choose sources to begin."
    private var hasStarted = false
    var hasLoadedSharediCloudState = false

    private let persistence: ConfigurationStore
    @ObservationIgnored private let scheduler = BackgroundSyncScheduler()
    @ObservationIgnored let photoLibrary = ApplePhotoLibrary()
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
        if !UserDefaults.standard.bool(forKey: SupportDefaultsKey.hasCompletedOnboarding) {
            isOnboardingPresented = true
        }
        async let sources: Void = refreshSources()
        async let account: Void = restoreAccountConnection()
        _ = await (sources, account)
        await refreshSharediCloudState()
    }

    func saveConfiguration(triggerSync: Bool = false) {
        do {
            try persistence.saveConfiguration(configuration)
            configureScheduler()
            try applyLaunchAtLoginPreference()
            applyDockIconPreference()
            statusMessage = "Configuration saved."
            if hasLoadedSharediCloudState {
                Task { await publishSharediCloudState() }
            }
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

        statusMessage = "Sources refreshed."
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

    /// Creates or reuses one Apple Reminders list for each person already
    /// enabled in Skylight's Chore Chart, plus the shared Up for Grabs list.
    /// Skylight is deliberately the source of setup truth, so the frame must
    /// be configured before this action is available.
    func setupChoreListsFromSkylight() async {
        guard !isSettingUpChoreLists else { return }
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
        isSettingUpChoreLists = true
        defer { isSettingUpChoreLists = false }

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

            var createdCount = 0
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
                    createdCount += 1
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
            saveConfiguration(triggerSync: true)
            let reused = links.count - createdCount
            statusMessage = "Chore lists are ready."
            appendActivity(.init(
                level: .success,
                area: .chores,
                message: "Chore setup created \(createdCount) Apple Reminders list\(createdCount == 1 ? "" : "s") and reused \(reused)."
            ))
        } catch {
            recordSourceError(error, area: .chores)
        }
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
    private func recordAppliedChanges(_ count: Int) {
        let defaults = UserDefaults.standard
        if count > 0 {
            defaults.set(lifetimeAppliedChanges + count, forKey: SupportDefaultsKey.lifetimeAppliedChanges)
        }
        guard donationPromptMilestone == nil, !isOnboardingPresented else { return }
        let context = SupportPromptPolicy.Context(
            isConnected: isSkylightConnected,
            isSyncing: false,
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
        (try? await sessionManager.storedEmail()) ?? ""
    }

    /// Disconnects the Skylight account: revokes the session (best effort) and
    /// deletes the stored email, password, and OAuth tokens from the Keychain.
    /// Mappings and sync history stay, so signing back in resumes where the
    /// account left off.
    func signOut() async {
        guard !isConnecting else { return }
        do {
            try await sessionManager.signOut()
        } catch {
            recordSourceError(error, area: .account)
            return
        }
        skylightFrames = []
        skylightDevices = []
        skylightAlbums = []
        skylightLists = []
        skylightMealCategories = []
        skylightChoreCategories = []
        connectionError = nil
        multiClientWarning = nil
        statusMessage = "Signed out of Skylight."
        appendActivity(.init(
            level: .info,
            area: .account,
            message: "Signed out of Skylight. The saved email, password, and session tokens were removed from the Keychain. Mappings were kept."
        ))
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

        do {
           try persistence.saveConfiguration(configuration)
           let client = try await sessionManager.client(configuration: configuration.account)
            // Notes automation reaches Apple Notes over Apple Events, which need
            // a live target process. A scheduled sync usually runs while Notes
            // is closed, so launch it first (without stealing focus); otherwise
            // the recipe and meal domains fail with "Connection is invalid".
            if syncConfiguration.recipeSelection.enabled || syncConfiguration.mealSelection.enabled {
                try? await launchNotesIfNeeded()
            }
            await importSharedSyncState()
            let coordinator = SyncCoordinator.live(apiClient: client)
            let summary = try await coordinator.sync(configuration: syncConfiguration)
            try await refreshSkylightDestinations(using: client)
            record(summary.photos, area: .photos, dryRun: summary.dryRun)
            record(summary.reminders, area: .reminders, dryRun: summary.dryRun)
            record(summary.chores, area: .chores, dryRun: summary.dryRun)
            record(summary.recipes, area: .recipes, dryRun: summary.dryRun)
            record(summary.meals, area: .meals, dryRun: summary.dryRun)
            lastSyncAt = .now
            lastSyncFailed = false
            if !summary.dryRun {
                recordAppliedChanges(summary.totalApplied)
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

    /// Disables Chore Chart sync for a mapping and cleans up what it created.
    /// The mode chooses which side's chores to keep; the auto-created Apple
    /// chore lists are removed whenever the Apple side is cleared.
    func removeChoreMapping(_ mapping: ChoreMapping, mode: ChoreTeardownMode) async {
        let frameID = mapping.frameID.trimmed.isEmpty
            ? configuration.account.frameID.trimmed
            : mapping.frameID.trimmed
        if !frameID.isEmpty, isSkylightConnected {
            do {
                let client = try await sessionManager.client(configuration: configuration.account)
                let coordinator = SyncCoordinator.live(apiClient: client)
                let result = try await coordinator.teardownChoreMapping(
                    mappingID: mapping.id,
                    frameID: frameID,
                    mode: mode,
                    appleListIDs: choreListIDs(for: mapping)
                )
                recordChoreTeardown(result)
            } catch {
                recordSourceError(error, area: .chores)
            }
        }
        configuration.choreMappings.removeAll { $0.id == mapping.id }
        saveConfiguration()
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
            skylightChoreCategories = []
            return
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
