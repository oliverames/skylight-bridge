import SwiftUI

/// Contextual thank-you sheet shown after the bridge has synchronized a
/// milestone number of changes. Eligibility lives in SupportPromptPolicy.
struct DonationPromptView: View {
    static let donationURL = URL(string: "https://buymeacoffee.com/oliverames")!

    let syncedChangeCount: Int
    let onSupport: () -> Void
    let onMaybeLater: () -> Void
    let onDontAskAgain: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: heroIconSize, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.top, 24)

            VStack(spacing: 10) {
                Text("Enjoying Skylight Bridge?")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(spacing: 8) {
                    Text("The bridge has synchronized \(syncedChangeCount.formatted()) changes between your Apple apps and your frame.")
                    Text("If it saves your family time, you can help fund the next release.")
                    Text("Skylight Bridge stays free either way.")
                }
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button {
                    onSupport()
                } label: {
                    Label("Donate to Skylight Bridge", systemImage: "cup.and.saucer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("donation.support")

                Button {
                    onMaybeLater()
                } label: {
                    Text("Maybe Later")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button("Don't Ask Again") {
                    onDontAskAgain()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 22)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 440)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Donation Prompt") {
    DonationPromptView(
        syncedChangeCount: 512,
        onSupport: {},
        onMaybeLater: {},
        onDontAskAgain: {}
    )
}
