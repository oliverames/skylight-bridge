import AppKit
import SwiftUI

/// Shared building blocks for the grouped-settings layout used across the app.
/// The content areas use standard macOS grouped forms; Liquid Glass appears only
/// in system chrome such as the toolbar and sidebar.

enum AppVersion {
    static var description: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

/// Flat capsule badge, like the "Disabled" and "Shown as fallback" chips in
/// native grouped settings.
struct StatusBadge: View {
    enum Tone {
        case neutral
        case positive
        case warning
    }

    let title: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }
            Text(title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color? {
        switch tone {
        case .neutral: nil
        case .positive: .green
        case .warning: .orange
        }
    }
}

/// Section header with a bold title and a plain-language subtitle.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

/// "Tip" capsule with explanatory text, used as a section footer.
struct TipFooter: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Tip")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: Capsule())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

/// Permission row: title and detail on the left, status and the grant or
/// refresh control on the right.
struct AccessRow: View {
    let title: String
    let detail: String
    let isAuthorized: Bool
    /// After the user denies access, macOS never shows the permission prompt
    /// again, so "Allow Access" would silently do nothing. Callers pass the
    /// System Settings privacy pane to link instead (e.g. "Privacy_Photos").
    var deniedPane: String? = nil
    var isDenied: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(isDenied
                    ? "Access was denied. Grant it in System Settings, then return here."
                    : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            StatusBadge(
                title: isAuthorized ? "Granted" : (isDenied ? "Denied" : "Not granted"),
                tone: isAuthorized ? .positive : .warning
            )
            if isDenied, let deniedPane {
                Button("Open System Settings…") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?\(deniedPane)"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                Button(isAuthorized ? "Refresh" : "Allow Access", action: action)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Row for a configured mapping: leading icon, title and detail lines, then
/// status, edit, enable, and overflow controls.
struct MappingRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var caption: String? = nil
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            StatusBadge(
                title: isEnabled ? "Enabled" : "Paused",
                tone: isEnabled ? .positive : .neutral
            )

            // An inline Button in a Form/List row needs an explicit style, or
            // macOS routes the click to the row and the button never fires.
            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)

            Toggle("Enabled", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Enable \(title)")

            Menu {
                Button("Delete Mapping", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More options for \(title)")
        }
        .padding(.vertical, 4)
    }
}

/// Quiet placeholder row shown when a section has nothing configured yet.
struct EmptyConfigurationRow: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
    }
}

/// Sheet footer with Cancel and a prominent confirm action, separated from the
/// form by a divider.
struct EditorFooter: View {
    let confirmTitle: String
    let canConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
            .padding(12)
        }
        .background(.bar)
    }
}

/// Binding wrapper that persists the configuration after every change.
@MainActor
func savingBinding(_ source: Binding<Bool>, onSet: @escaping @MainActor () -> Void) -> Binding<Bool> {
    Binding(
        get: { source.wrappedValue },
        set: { value in
            source.wrappedValue = value
            onSet()
        }
    )
}
