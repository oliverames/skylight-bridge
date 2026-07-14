import SwiftUI

struct ActivityView: View {
    let store: AppStore
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                if store.activity.isEmpty {
                    EmptyConfigurationRow(text: "No activity yet. Preview and live sync results appear here.")
                } else {
                    ForEach(store.activity) { entry in
                        ActivityRow(entry: entry)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(
                        title: "Recent activity",
                        subtitle: "Sync previews, applied changes, conflicts, and errors."
                    )
                    Spacer()
                    if !store.activity.isEmpty {
                        StatusBadge(title: activityCountDescription)
                        Button("Clear…") { isConfirmingClear = true }
                            .controlSize(.small)
                    }
                }
                .textCase(nil)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
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

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.area.rawValue.capitalized)
                        .fontWeight(.medium)
                    if entry.isDryRun {
                        StatusBadge(title: "Preview")
                    }
                    Spacer()
                    Text(entry.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
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
