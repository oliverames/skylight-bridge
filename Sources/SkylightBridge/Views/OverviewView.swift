import SwiftUI

struct OverviewView: View {
    @Environment(\.openSettings) private var openSettings
    @Bindable var store: AppStore

    private let columns = [
        GridItem(.flexible(minimum: 260), spacing: 16),
        GridItem(.flexible(minimum: 260), spacing: 16)
    ]

    private var enabledPhotoMappingCount: Int {
        store.configuration.photoMappings.filter(\.enabled).count
    }

    private var enabledReminderMappingCount: Int {
        store.configuration.reminderMappings.filter(\.enabled).count
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(
                        title: "Skylight Bridge",
                        subtitle: "Choose exactly which Apple content is mirrored to your Skylight.",
                        systemImage: "rectangle.2.swap"
                    )

                    connectionCard

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        OverviewCard(
                            title: "Photos",
                            value: countDescription(enabledPhotoMappingCount, singular: "mapping"),
                            detail: "Albums, Favorites, or hand-picked photos",
                            systemImage: "photo.on.rectangle.angled",
                            action: { store.selection = .photos }
                        )
                        OverviewCard(
                            title: "Reminders",
                            value: countDescription(enabledReminderMappingCount, singular: "list"),
                            detail: "Whole lists or selected reminders only",
                            systemImage: "checklist",
                            action: { store.selection = .reminders }
                        )
                        OverviewCard(
                            title: "Recipes",
                            value: store.configuration.recipeSelection.folderTitle ?? "Not configured",
                            detail: selectionSummary(store.configuration.recipeSelection),
                            systemImage: "book.closed",
                            action: { store.selection = .recipes }
                        )
                        OverviewCard(
                            title: "Meals",
                            value: store.configuration.mealSelection.folderTitle ?? "Not configured",
                            detail: selectionSummary(store.configuration.mealSelection),
                            systemImage: "fork.knife",
                            action: { store.selection = .meals }
                        )
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Safe by default", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                            Label("Only configured sources are considered for sync.", systemImage: "checkmark.shield")
                            Label("Deletions apply only to Skylight objects created by this bridge.", systemImage: "lock.shield")
                            Label(store.configuration.dryRun ? "Dry run is on. No remote changes are made." : "Live sync is on.", systemImage: store.configuration.dryRun ? "eye" : "arrow.up.arrow.down")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Overview")
    }

    private var connectionCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: store.isSkylightConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                    .font(.title)
                    .foregroundStyle(store.isSkylightConnected ? Color.green : Color.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isSkylightConnected ? "Ready to sync" : "Connect your Skylight account")
                        .font(.headline)
                    Text(store.isSkylightConnected
                         ? store.statusMessage
                         : "Open Settings to connect. Your credentials stay in the macOS Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let lastSyncAt = store.lastSyncAt {
                    StatusPill(title: lastSyncAt.formatted(.relative(presentation: .named)), systemImage: "clock")
                }

                if !store.isSkylightConnected {
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func selectionSummary(_ selection: NotesSelection) -> String {
        switch selection.selectionMode {
        case .everything:
            "Every note in the selected folder"
        case .selectedItems:
            "\(selection.selectedNoteIDs.count) selected notes"
        }
    }

    private func countDescription(_ count: Int, singular: String) -> String {
        "\(count) \(count == 1 ? singular : singular + "s")"
    }
}

private struct OverviewCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .padding(18)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.interactive(),
            in: .rect(corners: .concentric(minimum: .fixed(18)))
        )
        .accessibilityHint("Open \(title) settings")
    }
}
