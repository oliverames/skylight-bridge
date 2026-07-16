import Foundation

/// Converts CloudKit setup failures into concise, actionable activity messages.
/// A production-signed app cannot create record types, so this error needs a
/// CloudKit schema deployment rather than another user-facing retry warning.
enum SharedCloudKitFailure {
    static func isProductionSchemaConfigurationError(_ error: any Error) -> Bool {
        let description = error.localizedDescription
        return description.localizedCaseInsensitiveContains("cannot create new type") &&
            description.localizedCaseInsensitiveContains("production schema")
    }

    static func activityMessage(for error: any Error, savedLocally: Bool) -> String {
        if isProductionSchemaConfigurationError(error) {
            let prefix = savedLocally ? "Saved on this Mac. " : ""
            return prefix + "iCloud sharing needs its schema deployed to production before it can sync."
        }
        let prefix = savedLocally
            ? "Saved on this Mac. iCloud sharing will retry when available: "
            : "iCloud sharing is unavailable: "
        return prefix + error.localizedDescription
    }
}
