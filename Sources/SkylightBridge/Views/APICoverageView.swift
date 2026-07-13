import SwiftUI

struct APICoverageView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "API Coverage",
                    subtitle: "The client covers discovered Skylight resources even when the app intentionally does not expose a sync interface for them."
                )

                Label(
                    "Skylight does not publish this API. Endpoints are versioned, tested independently, and may change without notice.",
                    systemImage: "exclamationmark.triangle"
                )
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                ForEach(SkylightEndpointCatalog.groups) { group in
                    GroupBox(group.name) {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(group.endpoints) { endpoint in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(endpoint.method)
                                        .font(.caption.monospaced().bold())
                                        .frame(width: 52, alignment: .leading)
                                    Text(endpoint.path)
                                        .font(.callout.monospaced())
                                    Spacer()
                                    Text(endpoint.evidence.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("API Coverage")
    }
}
