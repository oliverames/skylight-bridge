import AppKit
import SwiftUI

/// Account, Sync, and Diagnostics live directly in the main window's sidebar so
/// that sign-in and every setting are reachable without a separate Settings
/// pane. Skylight Bridge is a menu-bar-first app, so one window holds it all.

struct AccountView: View {
    @Bindable var store: AppStore
    @State private var email = ""
    @State private var password = ""

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
                    Picker("Frame", selection: $store.configuration.account.frameID) {
                        ForEach(store.skylightFrames) { frame in
                            Text(frame.attributes.name ?? "Unnamed Frame").tag(frame.id)
                        }
                    }
                    .onChange(of: store.configuration.account.frameID) {
                        Task { await store.selectFrame(store.configuration.account.frameID) }
                    }

                    if let device = store.skylightDevices.first(where: { $0.id == store.configuration.account.deviceID }) {
                        LabeledContent("Device", value: device.attributes.name ?? "Selected Automatically")
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
                    detail: store.notesAccessGranted ? "Authorized" : "Not requested",
                    isBlocked: false,
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
