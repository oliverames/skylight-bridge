import SwiftUI

struct ActivityView: View {
    let store: AppStore
    @State private var isConfirmingClear = false

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 10) {
                VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Activity",
                    subtitle: "Review sync previews, applied changes, conversions, conflicts, and errors.",
                    systemImage: "clock.arrow.circlepath"
                )

                if store.activity.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "No Activity Yet",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Preview and live sync results appear here.")
                        )
                        .frame(minHeight: 260)
                    }
                } else {
                    HStack {
                        Text("Recent activity")
                            .font(.title2.bold())
                        Spacer()
                        StatusPill(
                            title: activityCountDescription,
                            systemImage: "list.bullet"
                        )
                        Button("Clear", systemImage: "trash") {
                            isConfirmingClear = true
                        }
                        .buttonStyle(.glass)
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(store.activity) { entry in
                            ActivityEntryCard(entry: entry)
                        }
                    }
                }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Activity")
        .confirmationDialog(
            "Clear Activity?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Activity", role: .destructive) {
                store.clearActivity()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the saved activity history from this Mac.")
        }
    }

    private var activityCountDescription: String {
        "\(store.activity.count) \(store.activity.count == 1 ? "entry" : "entries")"
    }
}

private struct ActivityEntryCard: View {
    let entry: ActivityEntry

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(entry.area.rawValue.capitalized)
                            .font(.headline)
                        if entry.isDryRun {
                            StatusPill(title: "Preview", systemImage: "eye")
                        }
                        Spacer()
                        Text(entry.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch entry.level {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch entry.level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
