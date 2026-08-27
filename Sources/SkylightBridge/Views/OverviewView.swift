import AppKit
import SwiftUI

struct OverviewView: View {
    @Bindable var store: AppStore

    private var enabledPhotoMappingCount: Int {
        store.configuration.photoMappings.filter(\.enabled).count
    }

    private var enabledReminderMappingCount: Int {
        store.configuration.reminderMappings.filter(\.enabled).count
    }

    var body: some View {
        Form {
            if let recoveryStatusMessage = store.recoveryStatusMessage {
                Section("Recovery required") {
                    Label(
                        recoveryStatusMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            Section {
                appRow
                connectionRow
                if let lastSyncAt = store.lastSyncAt {
                    LabeledContent("Last sync") {
                        Text(lastSyncAt.formatted(.relative(presentation: .named)))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                sourceRow(
                    title: "Photos",
                    systemImage: "photo.on.rectangle.angled",
                    value: countDescription(enabledPhotoMappingCount, singular: "mapping"),
                    detail: "Albums, Favorites, or hand-picked photos. Push only.",
                    destination: .photos
                )
                sourceRow(
                    title: "Reminders",
                    systemImage: "checklist",
                    value: countDescription(enabledReminderMappingCount, singular: "mapping"),
                    detail: "Whole lists or selected reminders. One-way or two-way.",
                    destination: .reminders
                )
                sourceRow(
                    title: "Recipes",
                    systemImage: "book.closed",
                    value: notesSelectionValue(store.configuration.recipeSelection),
                    detail: recipesDetail,
                    destination: .recipes
                )
                // Temporarily hide the unfinished Meals workflow from the overview.
                // sourceRow(
                //     title: "Meals",
                //     systemImage: "fork.knife",
                //     value: notesSelectionValue(store.configuration.mealSelection),
                //     detail: "Dated meal lines from a Notes folder. Push only.",
                //     destination: .meals
                // )
            } header: {
                SectionHeader(
                    title: "Sources",
                    subtitle: "Only content you map here is ever considered for sync."
                )
            } footer: {
                TipFooter(text: store.configuration.dryRun
                    ? "Preview mode is on. Syncs are planned and logged without changing Apple or Skylight data."
                    : "Live sync is on. Deletions only ever touch bridge-managed items.")
            }
        }
        .formStyle(.grouped)
        .groupedPageLayout()
        .navigationTitle("Overview")
    }

    private var appRow: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Skylight Bridge")
                    .font(.headline)
                Text("Version \(AppVersion.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            // Same conditions as the toolbar's Sync button, so the two never
            // disagree about whether a sync can run.
            Button(syncButtonTitle) {
                Task { await store.syncNow() }
            }
            .disabled(!store.canSyncNow)
            .help(syncButtonHelp)
        }
        .padding(.vertical, 4)
    }

    private var connectionRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.isSkylightConnected
                    ? "Connected to Skylight"
                    : "Connect your Skylight account")
                Text(store.isSkylightConnected
                    ? connectedFrameDescription
                    : "Credentials stay in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            StatusBadge(
                title: store.isSkylightConnected ? "Connected" : "Not connected",
                tone: store.isSkylightConnected ? .positive : .warning
            )
            if !store.isSkylightConnected {
                Button("Sign In…") { store.selection = .account }
            }
        }
        .padding(.vertical, 2)
    }

    private var syncButtonTitle: String {
        if store.isSyncing {
            return "Syncing…"
        }
        return store.configuration.dryRun ? "Preview Sync" : "Sync Now"
    }

    private var syncButtonHelp: String {
        if !store.isSkylightConnected {
            return "Sign in to Skylight to sync"
        }
        if !store.hasEnabledVisibleSync {
            return "Add and enable a source mapping first"
        }
        return "Synchronize enabled sources"
    }

    private var connectedFrameDescription: String {
        let frame = store.skylightFrames.first { $0.id == store.configuration.account.frameID }
        if let name = frame?.attributes.name, !name.isEmpty {
            return "Syncing with \(name)."
        }
        return "Signed in. Syncs run on the schedule in Sync settings."
    }

    private func notesSelectionValue(_ selection: NotesSelection) -> String {
        guard let title = selection.folderTitle else { return "Not configured" }
        return selection.enabled ? title : "\(title) (paused)"
    }

    private var recipesDetail: String {
        store.configuration.recipeSelection.direction == .twoWay
            ? "Recipe notes sync both ways with the Skylight recipe box."
            : "Recipe notes from a Notes folder. Push only."
    }

    private func sourceRow(
        title: String,
        systemImage: String,
        value: String,
        detail: String,
        destination: NavigationSection
    ) -> some View {
        Button {
            store.selection = destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open \(title)")
    }

    private func countDescription(_ count: Int, singular: String) -> String {
        "\(count) \(count == 1 ? singular : singular + "s")"
    }
}
