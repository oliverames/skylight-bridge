import AppKit
import SwiftUI

/// Account, Sync, and Diagnostics live directly in the main window's sidebar so
/// that sign-in and every setting are reachable without a separate Settings
/// pane. Skylight Bridge is a menu-bar-first app, so one window holds it all.

struct AccountView: View {
    @Bindable var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var isConfirmingSignOut = false

    var body: some View {
        Form {
            Section("Skylight") {
                LabeledContent("Status") {
                    StatusBadge(
                        title: store.isSkylightConnected ? "Connected" : "Not connected",
                        tone: store.isSkylightConnected ? .positive : .warning
                    )
                }

                if !store.skylightFrames.isEmpty {
                    Picker("Frame", selection: Binding(
                        get: { store.configuration.account.frameID },
                        set: { replacement in
                            let previous = store.configuration.account.frameID
                            Task {
                                await store.selectFrame(replacement, replacing: previous)
                            }
                        }
                    )) {
                        ForEach(store.skylightFrames) { frame in
                            Text(frame.attributes.name ?? "Unnamed Frame").tag(frame.id)
                        }
                    }
                    .disabled(store.isConnecting || store.isSyncing)

                    if let device = store.skylightDevices.first(where: { $0.id == store.configuration.account.deviceID }) {
                        LabeledContent("Device", value: device.attributes.name ?? "Selected Automatically")
                    }
                }

                if store.isSkylightConnected {
                    LabeledContent("Session") {
                        Button("Sign Out…") { isConfirmingSignOut = true }
                            .disabled(store.isConnecting || store.isSyncing)
                    }
                }
            }

            Section {
                TextField("Skylight email", text: $email)
                    .textContentType(.username)
                SecureField("Skylight password", text: $password)
                    .textContentType(.password)

                HStack {
                    Spacer()
                    Button(store.isConnecting ? "Connecting…" : (store.isSkylightConnected ? "Reconnect" : "Sign In")) {
                        Task {
                            await store.saveAccountCredentials(email: email, password: password)
                            password = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isConnecting || email.trimmed.isEmpty || password.isEmpty)
                    .accessibilityIdentifier("account.connect")
                }

                if let connectionError = store.connectionError {
                    Label(connectionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                       .accessibilityIdentifier("account.connectionError")
               }
                if let multiClientWarning = store.multiClientWarning {
                    Label(multiClientWarning, systemImage: "exclamationmark.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("account.multiClientWarning")
                }
            } header: {
                SectionHeader(
                    title: "Sign in to Skylight",
                    subtitle: store.isSkylightConnected
                        ? "You are connected. Enter your password to reconnect or switch accounts."
                        : "Enter your Skylight email and password to connect."
                )
            } footer: {
                Text("Credentials and OAuth tokens are stored in the macOS Keychain. They are never written to app logs or configuration files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple access") {
                accessRow(
                    title: "Photos",
                    isAuthorized: store.photosAuthorizationStatus == .fullAccess,
                    detail: store.photosAuthorizationStatus.label,
                    isBlocked: store.photosAuthorizationStatus.isBlocked,
                    privacyPane: "Privacy_Photos"
                )
                accessRow(
                    title: "Reminders",
                    isAuthorized: store.remindersAuthorizationStatus == .fullAccess,
                    detail: store.remindersAuthorizationStatus.label,
                    isBlocked: store.remindersAuthorizationStatus.isBlocked,
                    privacyPane: "Privacy_Reminders"
                )
                accessRow(
                    title: "Notes",
                    isAuthorized: store.notesAccessGranted,
                    detail: store.notesAccessGranted
                        ? "Authorized"
                        : (store.notesAccessDenied ? "Denied" : "Not requested"),
                    isBlocked: store.notesAccessDenied,
                    privacyPane: "Privacy_Automation"
                )
            }
        }
        .formStyle(.grouped)
        .groupedPageLayout()
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Account")
        .task {
            if email.isEmpty {
                email = await store.storedAccountEmail()
            }
        }
        .confirmationDialog(
            "Sign Out of Skylight?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await store.signOut()
                    email = ""
                    password = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved email, password, and session tokens are removed from the macOS Keychain, and scheduled syncs stop until you sign in again. Mappings and sync history are kept.")
        }
    }

    @ViewBuilder
    private func accessRow(
        title: String,
        isAuthorized: Bool,
        detail: String,
        isBlocked: Bool,
        privacyPane: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Image(systemName: isAuthorized ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(isAuthorized ? Color.green : Color.secondary)
                Text(detail)
                    .foregroundStyle(.primary)
                if isBlocked {
                    // macOS never re-prompts after a denial; the only path back
                    // is System Settings.
                    Button("Open System Settings…") {
                        openPrivacyPane(privacyPane)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SyncSettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        Form {
            Section("Schedule") {
                Stepper(
                    "Sync every \(store.configuration.syncIntervalMinutes) minutes",
                    value: $store.configuration.syncIntervalMinutes,
                    in: 10...240,
                    step: 5
                )
                Toggle("Launch at login", isOn: $store.configuration.launchAtLogin)
                Toggle("Hide Dock icon", isOn: $store.configuration.hideDockIcon)
                if store.configuration.hideDockIcon {
                    Label(
                        "Skylight Bridge stays in the menu bar. Reopen this window from the menu bar icon.",
                        systemImage: "menubar.arrow.up.rectangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Safety") {
                Toggle("Preview changes without applying them", isOn: $store.configuration.dryRun)
                Label(
                    store.configuration.dryRun
                        ? "Preview mode is on. Syncs are planned and logged without changing Apple or Skylight data."
                        : "Live sync is on. Enabled mappings can change Skylight and, for reverse or two-way Reminders mappings, Apple Reminders.",
                    systemImage: store.configuration.dryRun ? "eye" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(store.configuration.dryRun ? Color.secondary : Color.orange)
            }

        }
        .formStyle(.grouped)
        .groupedPageLayout()
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Sync")
        // Mapping toggles elsewhere autosave, so these settings do too; a Save
        // button here silently lost changes on quit and made "Hide Dock icon"
        // appear broken until pressed.
        .onChange(of: store.configuration.syncIntervalMinutes) { store.saveConfiguration() }
        .onChange(of: store.configuration.launchAtLogin) { store.saveConfiguration() }
        .onChange(of: store.configuration.hideDockIcon) { store.saveConfiguration() }
        .onChange(of: store.configuration.dryRun) { store.saveConfiguration() }
    }
}

struct DiagnosticsView: View {
    @Bindable var store: AppStore

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: AppVersion.description)
                LabeledContent("Minimum system", value: "macOS 26")
                LabeledContent("Status", value: store.statusMessage)
                if let warning = SystemSecurityDiagnostics.blockedConsentPromptExplanation() {
                    BlockedPromptFix(warning: warning)
                }
            }

            Section("Advanced account details") {
                DisclosureGroup("Connection identifiers") {
                    LabeledContent("API host", value: store.configuration.account.baseURL)
                    LabeledContent("API version", value: store.configuration.account.apiVersion)
                    LabeledContent("Frame ID", value: redacted(store.configuration.account.frameID))
                    LabeledContent("Device ID", value: redacted(store.configuration.account.deviceID))
                }
            }

            Section("Discovered API coverage") {
                Text("The private Skylight client covers discovered resources even when the app intentionally provides no calendar, task, chore, or rewards sync interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                EndpointCoverageRows()
            }

            Section("Support") {
                Button("Refresh Skylight Resources") {
                    Task { await store.refreshSkylightDestinations() }
                }
                .disabled(!store.isSkylightConnected)
                Button("Open Activity") {
                    store.selection = .activity
                }
                LabeledContent("Enjoying Skylight Bridge?") {
                    Button("Donate…") {
                        store.donationPromptSupport()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .groupedPageLayout()
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Diagnostics")
    }

    private func redacted(_ value: String) -> String {
        guard value.count > 8 else { return value.isEmpty ? "Not selected" : "••••" }
        return "\(value.prefix(4))…\(value.suffix(4))"
    }
}

/// Shown when macOS is suppressing privacy prompts because a boot argument
/// disables Apple Mobile File Integrity. The app never edits the privacy
/// database itself; it explains the condition and hands the user the exact
/// Terminal commands to run, plus a shortcut to the System Settings pane.
private struct BlockedPromptFix: View {
    let warning: String
    @State private var scriptURL: URL?
    @State private var failureMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(warning)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Open Privacy Settings", action: openPrivacySettings)
                Button("Save Fix Script…", action: saveScript)
            }
            if let scriptURL {
                Text("Saved the script and copied its Terminal command. Paste this in Terminal, press Return, then reopen Skylight Bridge and click Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SystemSecurityDiagnostics.permissionGrantCommand(forScriptAt: scriptURL))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if let failureMessage {
                Text(failureMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("The script grants access by editing this Mac's privacy database, which only works while System Integrity Protection is disabled. Open it and read it before running it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Writes the script to disk, reveals it so the user can read it first, and
    /// copies the one-line command that runs it. Copying the script body itself
    /// did not work: zsh treats the `!` in its shebang as a history event and
    /// rejects the paste.
    private func saveScript() {
        do {
            let url = try SystemSecurityDiagnostics.writePermissionGrantScript()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(
                SystemSecurityDiagnostics.permissionGrantCommand(forScriptAt: url),
                forType: .string
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
            failureMessage = nil
            scriptURL = url
        } catch {
            scriptURL = nil
            failureMessage = "Could not save the script: \(error.localizedDescription)"
        }
    }
}

private struct EndpointCoverageRows: View {
    var body: some View {
        ForEach(SkylightEndpointCatalog.groups) { group in
            DisclosureGroup(group.name) {
                ForEach(group.endpoints) { endpoint in
                    LabeledContent {
                        Text(endpoint.evidence.label)
                            .foregroundStyle(.secondary)
                    } label: {
                        HStack(spacing: 8) {
                            Text(endpoint.method)
                                .font(.caption.monospaced().bold())
                                .frame(width: 48, alignment: .leading)
                            Text(endpoint.path)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}
