import Foundation

struct ReminderAdoptionPair: Equatable, Sendable {
    let appleID: String
    let skylightID: String
}

enum ReminderSyncPlanner {
    /// Pairs unlinked Apple reminders with unlinked Skylight items whose title and
    /// completion state match, so syncing into an existing list links equal items
    /// instead of duplicating them. Pairing is deterministic: both sides are
    /// consumed in identifier order.
    static func adoptionPairs(
        apple: [ReminderSnapshot],
        skylight: [SkylightListItemSnapshot],
        links: [ReminderSyncLink]
    ) -> [ReminderAdoptionPair] {
        let linkedAppleIDs = Set(links.map(\.appleID))
        let linkedSkylightIDs = Set(links.map(\.skylightID))

        var candidatesByKey: [String: [SkylightListItemSnapshot]] = [:]
        for item in skylight where !linkedSkylightIDs.contains(item.id) {
            candidatesByKey[matchKey(title: item.title, isCompleted: item.isCompleted), default: []]
                .append(item)
        }
        for key in candidatesByKey.keys {
            candidatesByKey[key]?.sort { $0.id < $1.id }
        }

        var pairs: [ReminderAdoptionPair] = []
        let unlinkedApple = apple
            .filter { !linkedAppleIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        for reminder in unlinkedApple {
            let key = matchKey(title: reminder.title, isCompleted: reminder.isCompleted)
            guard var candidates = candidatesByKey[key], !candidates.isEmpty else { continue }
            pairs.append(
                ReminderAdoptionPair(appleID: reminder.id, skylightID: candidates.removeFirst().id)
            )
            candidatesByKey[key] = candidates
        }
        return pairs
    }

   private static func matchKey(title: String, isCompleted: Bool) -> String {
       "\(title.trimmed.lowercased())\u{0}\(isCompleted)"
   }

    /// A secondary adoption pass that pairs remaining unlinked items by title
    /// alone, ignoring completion state. This catches the common
    /// disconnect/reconnect case where one side toggled a reminder's
    /// completion while the mapping was inactive, so the title still matches
    /// but the completion state diverged. Without this pass, both items would
    /// be treated as new unlinked items and duplicated on the other side.
    /// Pairing is deterministic by identifier order, and each side's items
    /// already consumed by the primary pass are excluded.
    static func titleOnlyAdoptionPairs(
        apple: [ReminderSnapshot],
        skylight: [SkylightListItemSnapshot],
        primaryPairs: [ReminderAdoptionPair]
    ) -> [ReminderAdoptionPair] {
        let consumedAppleIDs = Set(primaryPairs.map(\.appleID))
        let consumedSkylightIDs = Set(primaryPairs.map(\.skylightID))

        var candidatesByTitle: [String: [SkylightListItemSnapshot]] = [:]
        for item in skylight where !consumedSkylightIDs.contains(item.id) {
            candidatesByTitle[titleKey(item.title), default: []].append(item)
        }
        for key in candidatesByTitle.keys {
            candidatesByTitle[key]?.sort { $0.id < $1.id }
        }

        var pairs: [ReminderAdoptionPair] = []
        let unlinkedApple = apple
            .filter { !consumedAppleIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        for reminder in unlinkedApple {
            let key = titleKey(reminder.title)
            guard var candidates = candidatesByTitle[key], !candidates.isEmpty else { continue }
            pairs.append(
                ReminderAdoptionPair(appleID: reminder.id, skylightID: candidates.removeFirst().id)
            )
            candidatesByTitle[key] = candidates
        }
        return pairs
    }

    private static func titleKey(_ title: String) -> String {
        title.trimmed.lowercased()
    }

    static func plan(
        apple: [ReminderSnapshot],
        skylight: [SkylightListItemSnapshot],
        links: [ReminderSyncLink],
        direction: ReminderSyncDirection,
        conflictPolicy: SyncConflictPolicy
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
        conflictPolicy: SyncConflictPolicy
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
        conflictPolicy: SyncConflictPolicy
    ) -> ReminderSyncAction? {
        let appleChanged = apple.modifiedAt.isMeaningfullyAfter(link.lastAppleModifiedAt)
        let skylightChanged = skylight.modifiedAt.isMeaningfullyAfter(link.lastSkylightModifiedAt)

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
                link: link,
                appleChanged: appleChanged,
                skylightChanged: skylightChanged,
                conflictPolicy: conflictPolicy
            )
        }
    }

    private static func twoWayUpdateAction(
        apple: ReminderSnapshot,
        skylight: SkylightListItemSnapshot,
        link: ReminderSyncLink,
        appleChanged: Bool,
        skylightChanged: Bool,
        conflictPolicy: SyncConflictPolicy
    ) -> ReminderSyncAction? {
        switch (appleChanged, skylightChanged) {
        case (false, false):
            return nil
        case (true, false):
            return .updateRemote(appleID: apple.id, remoteID: skylight.id)
        case (false, true):
            return .updateApple(appleID: apple.id, remoteID: skylight.id)
        case (true, true):
            return bothChangedAction(
                apple: apple,
                skylight: skylight,
                link: link,
                conflictPolicy: conflictPolicy
            )
        }
    }

    /// When a linked reminder changed on both sides, merge the two portable
    /// fields (title and completion) independently against the last-synced
    /// baseline. A field only counts as a conflict when both sides changed that
    /// same field, in which case the conflict policy decides that one field. If
    /// the merged result already matches one side, reuse the plain one-way
    /// update; otherwise write the merged value to both sides.
    private static func bothChangedAction(
        apple: ReminderSnapshot,
        skylight: SkylightListItemSnapshot,
        link: ReminderSyncLink,
        conflictPolicy: SyncConflictPolicy
    ) -> ReminderSyncAction? {
        guard let baselineTitle = link.baselineTitle,
              let baselineCompleted = link.baselineCompleted else {
            // No field baseline (legacy record): fall back to whole-record policy.
            return wholeRecordWinner(apple: apple, skylight: skylight, conflictPolicy: conflictPolicy)
        }

        let mergedTitle = mergedField(
            baseline: baselineTitle,
            apple: apple.title,
            skylight: skylight.title,
            appleIsNewer: apple.modifiedAt >= skylight.modifiedAt,
            conflictPolicy: conflictPolicy
        )
        let mergedCompleted = mergedField(
            baseline: baselineCompleted,
            apple: apple.isCompleted,
            skylight: skylight.isCompleted,
            appleIsNewer: apple.modifiedAt >= skylight.modifiedAt,
            conflictPolicy: conflictPolicy
        )

        let matchesApple = mergedTitle == apple.title && mergedCompleted == apple.isCompleted
        let matchesSkylight = mergedTitle == skylight.title && mergedCompleted == skylight.isCompleted
        if matchesApple, matchesSkylight {
            return nil
        }
        if matchesApple {
            return .updateRemote(appleID: apple.id, remoteID: skylight.id)
        }
        if matchesSkylight {
            return .updateApple(appleID: apple.id, remoteID: skylight.id)
        }
        return .merge(
            appleID: apple.id,
            remoteID: skylight.id,
            title: mergedTitle,
            isCompleted: mergedCompleted
        )
    }

    private static func mergedField<Value: Equatable>(
        baseline: Value,
        apple: Value,
        skylight: Value,
        appleIsNewer: Bool,
        conflictPolicy: SyncConflictPolicy
    ) -> Value {
        let appleChanged = apple != baseline
        let skylightChanged = skylight != baseline
        switch (appleChanged, skylightChanged) {
        case (false, false):
            return baseline
        case (true, false):
            return apple
        case (false, true):
            return skylight
        case (true, true):
            // Both sides changed this same field: a true conflict.
            switch conflictPolicy {
            case .appleWins:
                return apple
            case .skylightWins:
                return skylight
            case .newestWins:
                return appleIsNewer ? apple : skylight
            }
        }
    }

    private static func wholeRecordWinner(
        apple: ReminderSnapshot,
        skylight: SkylightListItemSnapshot,
        conflictPolicy: SyncConflictPolicy
    ) -> ReminderSyncAction {
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

extension Date {
    /// Change detection against persisted sync baselines. The sealed state file
    /// stores dates as Unix seconds, and the 1970↔2001 epoch conversion loses
    /// sub-microsecond bits, so a decoded baseline can land fractionally below
    /// the live EventKit date it was copied from. A strict `>` then reports a
    /// phantom edit on every sync. No real edit is under a millisecond newer.
    func isMeaningfullyAfter(_ other: Date) -> Bool {
        timeIntervalSince(other) > 0.001
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
        case let .merge(appleID, remoteID, _, _):
            "4:\(appleID):\(remoteID)"
        case let .deleteRemote(remoteID):
            "5:\(remoteID)"
        case let .deleteApple(appleID):
            "6:\(appleID)"
        }
    }
}
