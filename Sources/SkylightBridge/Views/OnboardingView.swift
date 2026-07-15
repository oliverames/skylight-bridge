import SwiftUI

/// First-run setup guide that explains the real path to a first safe sync,
/// then hands off to Account for Skylight sign-in.
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

                        Text("Bring the photos, lists, chores, and recipes your household already uses to Skylight.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 44)
                    }
                    .padding(.top, 36)
                    .padding(.bottom, 28)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("A simple, safe setup")
                            .font(.headline)

                        OnboardingStepRow(
                            number: 1,
                            title: "Connect your Skylight",
                            description: "Sign in and choose the frame you want to manage. Connection details stay in your Mac’s Keychain."
                        )
                        OnboardingStepRow(
                            number: 2,
                            title: "Choose your first source",
                            description: "Start with Photos, Reminders, Chores, or recipes. You can add more whenever you are ready."
                        )
                        OnboardingStepRow(
                            number: 3,
                            title: "Preview before you sync",
                            description: "Preview mode is on by default. Review the planned changes in Activity before making anything live."
                        )
                    }
                    .padding(.horizontal, 32)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("You stay in control")
                                .font(.callout.weight(.semibold))
                            Text("Nothing is turned on automatically. Skylight Bridge reads only the sources you map, and you can stay in Preview mode until you are comfortable going live.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
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
                    Text("Connect Skylight")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.connectSkylight")

                Button("Set Up Later") {
                    onSkip()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.setUpLater")
            }
            .padding(.top, 20)
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 580, idealHeight: 620)
        .background(.regularMaterial)
    }
}

private struct OnboardingStepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "\(number).circle.fill")
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
        .accessibilityLabel("Step \(number): \(title). \(description)")
    }
}

#Preview("Onboarding") {
    OnboardingView(onGetStarted: {}, onSkip: {})
}
