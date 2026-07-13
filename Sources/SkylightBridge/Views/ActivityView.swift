import SwiftUI

struct ActivityView: View {
    let store: AppStore

    var body: some View {
        Group {
            if store.activity.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Sync previews, changes, conflicts, conversions, and errors appear here.")
                )
            } else {
                List(store.activity) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: entry.level))
                            .foregroundStyle(color(for: entry.level))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.area.rawValue.capitalized)
                                    .font(.headline)
                                if entry.isDryRun {
                                    Text("DRY RUN")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                                Spacer()
                                Text(entry.date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Activity")
    }

    private func icon(for level: ActivityLevel) -> String {
        switch level {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private func color(for level: ActivityLevel) -> Color {
        switch level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
