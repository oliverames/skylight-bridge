import SwiftUI

/// First-run welcome sheet: what the bridge does, what it never touches, and
/// a single call to action that lands on the Account screen to sign in.
struct OnboardingView: View {
    let onGetStarted: () -> Void
    let onSkip: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.2.swap")
                            .font(.system(size: heroIconSize, weight: .thin))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)

                        Text("Welcome to Skylight Bridge")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                    VStack(alignment: .leading, spacing: 20) {
                        OnboardingFeatureRow(
                            icon: "photo.on.rectangle.angled",
                            title: "Photos on the Frame",
                            description: "Mirror albums, Favorites, or hand-picked photos to your Skylight. Your Apple Photos library is never changed."
                        )
                        OnboardingFeatureRow(
                            icon: "checklist",
                            title: "Lists That Stay in Sync",
                            description: "Reminders and recipe notes sync both ways, so a task checked off on the frame is checked off on your iPhone too."
                        )
                        OnboardingFeatureRow(
                            icon: "lock.shield",
                            title: "Private by Design",
                            description: "Credentials live in the macOS Keychain, only content you map is ever read, and Preview mode shows every change before it happens."
                        )
                    }
                    .padding(.horizontal, 32)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text("Setup takes about two minutes: sign in to Skylight, allow access to the Apple apps you want to sync, then add your first mapping.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 20)
                    .padding(.horizontal, 32)
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                Button {
                    onGetStarted()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.getStarted")

                Button("Explore on My Own") {
                    onSkip()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 480, idealWidth: 500, minHeight: 560, idealHeight: 600)
        .background(.regularMaterial)
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Onboarding") {
    OnboardingView(onGetStarted: {}, onSkip: {})
}
