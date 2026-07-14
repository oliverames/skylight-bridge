import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular,
                in: .rect(corners: .concentric(minimum: .fixed(18)))
            )
    }
}

struct AccessCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let isAuthorized: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: isAuthorized ? "checkmark.circle.fill" : systemImage)
                    .font(.title2)
                    .foregroundStyle(isAuthorized ? Color.green : Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button(isAuthorized ? "Refresh" : buttonTitle, action: action)
                    .buttonStyle(.glass)
            }
        }
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(title)
                .foregroundStyle(.primary)
        }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}
