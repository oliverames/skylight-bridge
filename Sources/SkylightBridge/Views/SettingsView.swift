import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: AppStore
    @State private var selection: SettingsSection = .account
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            settingsContent
                .navigationTitle(selection.label)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbarBackground(.bar, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .frame(minWidth: 760, minHeight: 520)
        .task {
            email = await store.storedAccountEmail()
            await store.restoreAccountConnection()
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selection {
        case .account:
            accountSettings
        case .sync:
            syncSettings
        case .diagnostics:
            diagnosticsSettings
        }
    }

    private var accountSettings: some View {
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

            Section("Sign in") {
                TextField("Skylight email", text: $email)
                    .textContentType(.username)
                SecureField("Skylight password", text: $password)
                    .textContentType(.password)
                Text("Credentials and OAuth tokens are stored in the macOS Keychain. They are never written to app logs or configuration files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button(store.isConnecting ? "Connecting" : "Connect and Save") {
                        Task {
                            await store.saveAccountCredentials(email: email, password: password)
                            password = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isConnecting || email.trimmed.isEmpty || password.isEmpty)
                    .accessibilityIdentifier("settings.connect")
                }
            }

            Section("Apple access") {
                accessRow(
                    title: "Photos",
                    isAuthorized: store.photosAuthorizationStatus == .fullAccess,
                    detail: store.photosAuthorizationStatus.rawValue
                )
                accessRow(
                    title: "Reminders",
                    isAuthorized: store.remindersAuthorizationStatus == .fullAccess,
                    detail: store.remindersAuthorizationStatus.rawValue
                )
                accessRow(
                    title: "Notes",
                    isAuthorized: store.notesAccessGranted,
                    detail: store.notesAccessGranted ? "authorized" : "not requested"
                )
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var syncSettings: some View {
        Form {
            Section("Schedule") {
                Stepper(
                    "Sync every \(store.configuration.syncIntervalMinutes) minutes",
                    value: $store.configuration.syncIntervalMinutes,
                    in: 10...240,
                    step: 5
                )
                Toggle("Launch at login", isOn: $store.configuration.launchAtLogin)
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

            Section {
                HStack {
                    Spacer()
                    Button("Save Sync Settings") { store.saveConfiguration() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("settings.saveSync")
                }
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var diagnosticsSettings: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: versionDescription)
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
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .formStyle(.grouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private func accessRow(title: String, isAuthorized: Bool, detail: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Image(systemName: isAuthorized ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(isAuthorized ? Color.green : Color.secondary)
                Text(isAuthorized ? "Authorized" : detail.capitalized)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var versionDescription: String {
        AppVersion.description
    }

    private func redacted(_ value: String) -> String {
        guard value.count > 8 else { return value.isEmpty ? "Not selected" : "••••" }
        return "\(value.prefix(4))…\(value.suffix(4))"
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case account
    case sync
    case diagnostics

    var id: Self { self }

    var label: String {
        switch self {
        case .account: "Account"
        case .sync: "Sync"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .sync: "arrow.triangle.2.circlepath"
        case .diagnostics: "stethoscope"
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
