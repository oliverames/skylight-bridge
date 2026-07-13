import Foundation

enum ReminderSyncPlanner {
    static func plan(
        apple: [ReminderSnapshot],
        skylight: [SkylightListItemSnapshot],
        links: [ReminderSyncLink],
        direction: ReminderSyncDirection,
        conflictPolicy: ReminderConflictPolicy
    ) -> [ReminderSyncAction] {
        let appleByID = apple.indexedByID
        let skylightByID = skylight.indexedByID
        let linkedAppleIDs = Set(links.map(\.appleID))
        let linkedSkylightIDs = Set(links.map(\.skylightID))

        var actions = linkedActions(
            links: links,
            appleByID: appleByID,
            skylightByID: skylightByID,
            direction: direction,
            conflictPolicy: conflictPolicy
        )

        if direction != .skylightToApple {
            actions += appleByID.values
                .filter { !linkedAppleIDs.contains($0.id) }
                .map { .createRemote(appleID: $0.id) }
        }

        if direction != .appleToSkylight {
            actions += skylightByID.values
                .filter { !linkedSkylightIDs.contains($0.id) }
                .map { .createApple(remoteID: $0.id) }
        }

        return actions.sorted { $0.sortKey < $1.sortKey }
    }

    private static func linkedActions(
        links: [ReminderSyncLink],
        appleByID: [String: ReminderSnapshot],
        skylightByID: [String: SkylightListItemSnapshot],
        direction: ReminderSyncDirection,
        conflictPolicy: ReminderConflictPolicy
    ) -> [ReminderSyncAction] {
        links.compactMap { link in
            let appleItem = appleByID[link.appleID]
            let skylightItem = skylightByID[link.skylightID]

            switch (appleItem, skylightItem) {
            case let (.some(appleItem), .some(skylightItem)):
                return updateAction(
                    apple: appleItem,
                    skylight: skylightItem,
                    link: link,
                    direction: direction,
                    conflictPolicy: conflictPolicy
                )
            case (.some, .none) where direction == .appleToSkylight:
                return .createRemote(appleID: link.appleID)
            case (.none, .some) where direction == .appleToSkylight:
                return .deleteRemote(remoteID: link.skylightID)
            case (.none, .some) where direction == .skylightToApple:
                return .createApple(remoteID: link.skylightID)
            case (.some, .none) where direction == .skylightToApple:
                return .deleteApple(appleID: link.appleID)
            case (.some, .none) where direction == .twoWay:
                return .deleteApple(appleID: link.appleID)
            case (.none, .some) where direction == .twoWay:
                return .deleteRemote(remoteID: link.skylightID)
            default:
                return nil
            }
        }
    }

    private static func updateAction(
        apple: ReminderSnapshot,
        skylight: SkylightListItemSnapshot,
        link: ReminderSyncLink,
        direction: ReminderSyncDirection,
        conflictPolicy: ReminderConflictPolicy
    ) -> ReminderSyncAction? {
        let appleChanged = apple.modifiedAt > link.lastAppleModifiedAt
        let skylightChanged = skylight.modifiedAt > link.lastSkylightModifiedAt

        switch direction {
        case .appleToSkylight:
            return appleChanged
                ? .updateRemote(appleID: apple.id, remoteID: skylight.id)
                : nil
        case .skylightToApple:
            return skylightChanged
                ? .updateApple(appleID: apple.id, remoteID: skylight.id)
                : nil
        case .twoWay:
            return twoWayUpdateAction(
                apple: apple,
                skylight: skylight,
                appleChanged: appleChanged,
                skylightChanged: skylightChanged,
                conflictPolicy: conflictPolicy
            )
        }
    }

    private static func twoWayUpdateAction(
        apple: ReminderSnapshot,
        skylight: SkylightListItemSnapshot,
        appleChanged: Bool,
        skylightChanged: Bool,
        conflictPolicy: ReminderConflictPolicy
    ) -> ReminderSyncAction? {
        switch (appleChanged, skylightChanged) {
        case (false, false):
            return nil
        case (true, false):
            return .updateRemote(appleID: apple.id, remoteID: skylight.id)
        case (false, true):
            return .updateApple(appleID: apple.id, remoteID: skylight.id)
        case (true, true):
            switch conflictPolicy {
            case .appleWins:
                return .updateRemote(appleID: apple.id, remoteID: skylight.id)
            case .skylightWins:
                return .updateApple(appleID: apple.id, remoteID: skylight.id)
            case .newestWins:
                if skylight.modifiedAt > apple.modifiedAt {
                    return .updateApple(appleID: apple.id, remoteID: skylight.id)
                }
                return .updateRemote(appleID: apple.id, remoteID: skylight.id)
            }
        }
    }
}

private extension Array where Element == ReminderSnapshot {
    var indexedByID: [String: ReminderSnapshot] {
        reduce(into: [:]) { result, reminder in
            result[reminder.id] = reminder
        }
    }
}

private extension Array where Element == SkylightListItemSnapshot {
    var indexedByID: [String: SkylightListItemSnapshot] {
        reduce(into: [:]) { result, item in
            result[item.id] = item
        }
    }
}

private extension ReminderSyncAction {
    var sortKey: String {
        switch self {
        case let .createRemote(appleID):
            "0:\(appleID)"
        case let .createApple(remoteID):
            "1:\(remoteID)"
        case let .updateRemote(appleID, remoteID):
            "2:\(appleID):\(remoteID)"
        case let .updateApple(appleID, remoteID):
            "3:\(appleID):\(remoteID)"
        case let .deleteRemote(remoteID):
            "4:\(remoteID)"
        case let .deleteApple(appleID):
            "5:\(appleID)"
        }
    }
}
