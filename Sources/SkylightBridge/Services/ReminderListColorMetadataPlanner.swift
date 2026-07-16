import Foundation

struct ReminderListColorMetadataLink: Equatable, Sendable {
    let baselineAppleColor: String?
    let baselineSkylightColor: String?
}

enum ReminderListColorMetadataAction: Equatable, Sendable {
    case updateRemote(color: String)
    case updateApple(color: String)
}

/// Plans color changes for valid color values. Clearing a color is deliberately
/// not attempted because the Skylight API does not document a clear operation
/// for its optional color field.
enum ReminderListColorMetadataPlanner {
    static func plan(
        appleColor: String?,
        skylightColor: String?,
        link: ReminderListColorMetadataLink,
        direction: ReminderSyncDirection,
        conflictPolicy: SyncConflictPolicy
    ) -> ReminderListColorMetadataAction? {
        guard appleColor != skylightColor else {
            return nil
        }

        let appleChanged = appleColor != link.baselineAppleColor
        let skylightChanged = skylightColor != link.baselineSkylightColor

        switch (appleChanged, skylightChanged) {
        case (false, false):
            return nil
        case (true, false):
            return remoteAction(color: appleColor, direction: direction)
        case (false, true):
            return appleAction(color: skylightColor, direction: direction)
        case (true, true):
            return conflictAction(
                appleColor: appleColor,
                skylightColor: skylightColor,
                direction: direction,
                conflictPolicy: conflictPolicy
            )
        }
    }

    private static func remoteAction(
        color: String?,
        direction: ReminderSyncDirection
    ) -> ReminderListColorMetadataAction? {
        guard let color else { return nil }
        switch direction {
        case .appleToSkylight, .twoWay:
            return .updateRemote(color: color)
        case .skylightToApple:
            return nil
        }
    }

    private static func appleAction(
        color: String?,
        direction: ReminderSyncDirection
    ) -> ReminderListColorMetadataAction? {
        guard let color else { return nil }
        switch direction {
        case .skylightToApple, .twoWay:
            return .updateApple(color: color)
        case .appleToSkylight:
            return nil
        }
    }

    private static func conflictAction(
        appleColor: String?,
        skylightColor: String?,
        direction: ReminderSyncDirection,
        conflictPolicy: SyncConflictPolicy
    ) -> ReminderListColorMetadataAction? {
        switch direction {
        case .appleToSkylight:
            return remoteAction(color: appleColor, direction: direction)
        case .skylightToApple:
            return appleAction(color: skylightColor, direction: direction)
        case .twoWay:
            switch conflictPolicy {
            case .appleWins, .newestWins:
                return remoteAction(color: appleColor, direction: direction)
            case .skylightWins:
                return appleAction(color: skylightColor, direction: direction)
            }
        }
    }
}
