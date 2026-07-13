import SwiftUI

struct OverviewView: View {
    let store: AppStore

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skylight Bridge")
                        .font(.largeTitle.bold())
                    Text("Choose exactly which Apple content is mirrored to your Skylight.")
                        .foregroundStyle(.secondary)
                }

                if store.configuration.account.frameID.isEmpty {
                    Label("Connect your Skylight account in Settings before the first sync. Frames and devices are discovered automatically.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    OverviewCard(
                        title: "Photos",
                        value: "\(store.configuration.photoMappings.filter(\.enabled).count) mappings",
                        detail: "Albums, Favorites, or hand-picked photos",
                        systemImage: "photo.on.rectangle.angled"
                    )
                    OverviewCard(
                        title: "Reminders",
                        value: "\(store.configuration.reminderMappings.filter(\.enabled).count) lists",
                        detail: "Whole lists or selected reminders only",
                        systemImage: "checklist"
                    )
                    OverviewCard(
                        title: "Recipes",
                        value: store.configuration.recipeSelection.folderTitle ?? "Not configured",
                        detail: selectionSummary(store.configuration.recipeSelection),
                        systemImage: "book.closed"
                    )
                    OverviewCard(
                        title: "Meals",
                        value: store.configuration.mealSelection.folderTitle ?? "Not configured",
                        detail: selectionSummary(store.configuration.mealSelection),
                        systemImage: "fork.knife"
                    )
                }

                GroupBox("Safety") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Only configured sources are considered for sync.", systemImage: "checkmark.shield")
                        Label("Deletions apply only to Skylight objects created by this bridge.", systemImage: "lock.shield")
                        Label(store.configuration.dryRun ? "Dry run is on. No remote changes are made." : "Live sync is on.", systemImage: store.configuration.dryRun ? "eye" : "arrow.up.arrow.down")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
    }

    private func selectionSummary(_ selection: NotesSelection) -> String {
        switch selection.selectionMode {
        case .everything:
            "Every note in the selected folder"
        case .selectedItems:
            "\(selection.selectedNoteIDs.count) selected notes"
        }
    }
}

private struct OverviewCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text(value)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        }
    }
}
