import AppKit
import SwiftUI

struct OverviewView: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable var store: AppStore

    private var enabledPhotoMappingCount: Int {
        store.configuration.photoMappings.filter(\.enabled).count
    }

    private var enabledReminderMappingCount: Int {
        store.configuration.reminderMappings.filter(\.enabled).count
    }

    var body: some View {
        Form {
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
                    value: countDescription(enabledReminderMappingCount, singular: "list"),
                    detail: "Whole lists or selected reminders. One-way or two-way.",
                    destination: .reminders
                )
                sourceRow(
                    title: "Recipes",
                    systemImage: "book.closed",
                    value: store.configuration.recipeSelection.folderTitle ?? "Not configured",
                    detail: recipesDetail,
                    destination: .recipes
                )
                sourceRow(
                    title: "Meals",
                    systemImage: "fork.knife",
                    value: store.configuration.mealSelection.folderTitle ?? "Not configured",
                    detail: "Dated meal lines from a Notes folder. Push only.",
                    destination: .meals
                )
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
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
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
            Button(syncButtonTitle) {
                Task { await store.syncNow() }
            }
            .disabled(store.isSyncing || !store.configuration.hasEnabledSync)
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
                    ? store.statusMessage
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
                Button("Open Settings…") { openSettings() }
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
