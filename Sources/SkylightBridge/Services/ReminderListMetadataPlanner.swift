import Foundation

struct ReminderListMetadataLink: Equatable, Sendable {
    let baselineAppleTitle: String
    let baselineSkylightTitle: String
}

enum ReminderListMetadataAction: Equatable, Sendable {
    case updateRemote(title: String)
    case updateApple(title: String)
}

/// Plans title changes for Apple Reminders and Skylight lists. List color uses
/// the companion color planner. The two APIs do not expose mutable-list clocks,
/// so simultaneous edits use the selected policy with Apple as the stable
/// fallback for the otherwise unresolvable `newestWins` case.
enum ReminderListMetadataPlanner {
    static func plan(
        appleTitle: String,
        skylightTitle: String,
        link: ReminderListMetadataLink,
        direction: ReminderSyncDirection,
        conflictPolicy: SyncConflictPolicy
    ) -> ReminderListMetadataAction? {
        guard appleTitle != skylightTitle else { return nil }

        switch direction {
        case .appleToSkylight:
            return .updateRemote(title: appleTitle)
        case .skylightToApple:
            return .updateApple(title: skylightTitle)
        case .twoWay:
            let appleChanged = appleTitle != link.baselineAppleTitle
            let skylightChanged = skylightTitle != link.baselineSkylightTitle
            switch (appleChanged, skylightChanged) {
            case (false, false):
                return nil
            case (true, false):
                return .updateRemote(title: appleTitle)
            case (false, true):
                return .updateApple(title: skylightTitle)
            case (true, true):
                switch conflictPolicy {
                case .skylightWins:
                    return .updateApple(title: skylightTitle)
                case .appleWins, .newestWins:
                    return .updateRemote(title: appleTitle)
                }
            }
        }
    }
}
