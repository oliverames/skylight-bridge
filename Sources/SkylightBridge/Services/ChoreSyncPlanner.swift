import Foundation

enum ChoreSyncPlanner {
    static func adoptionPairs(
        apple: [ChoreReminderSnapshot],
        skylight: [SkylightChoreSnapshot],
        links: [ChoreSyncLink]
    ) -> [ChoreAdoptionPair] {
        let linkedApple = Set(links.map(\.appleID))
        let linkedRemote = Set(links.map(\.skylightID))
        var remoteByKey: [String: [SkylightChoreSnapshot]] = [:]
        for item in skylight where !linkedRemote.contains(item.id) {
            remoteByKey[key(item.title, item.memberKey), default: []].append(item)
        }
        for candidateKey in remoteByKey.keys {
            remoteByKey[candidateKey]?.sort { $0.id < $1.id }
        }
        var result: [ChoreAdoptionPair] = []
        for item in apple.filter({ !linkedApple.contains($0.id) }).sorted(by: { $0.id < $1.id }) {
            let candidateKey = key(item.title, item.memberKey)
            guard var candidates = remoteByKey[candidateKey], !candidates.isEmpty else { continue }
            result.append(.init(appleID: item.id, skylightID: candidates.removeFirst().id))
            remoteByKey[candidateKey] = candidates
        }
        return result
    }

    static func plan(
        apple: [ChoreReminderSnapshot],
        skylight: [SkylightChoreSnapshot],
        links: [ChoreSyncLink],
        direction: ReminderSyncDirection,
        conflictPolicy: SyncConflictPolicy,
        today: String,
        todayDate: Date
    ) -> [ChoreSyncAction] {
        let appleByID = Dictionary(uniqueKeysWithValues: apple.map { ($0.id, $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: skylight.map { ($0.id, $0) })
        let linkedApple = Set(links.map(\.appleID))
        let linkedRemote = Set(links.map(\.skylightID))
        var actions: [ChoreSyncAction] = []

        for link in links {
            let appleItem = appleByID[link.appleID]
            let remoteItem = remoteByID[link.skylightID]
            switch (appleItem, remoteItem) {
            case let (appleItem?, remoteItem?):
                actions += pairActions(
                    apple: appleItem,
                    remote: remoteItem,
                    link: link,
                    direction: direction,
                    policy: conflictPolicy,
                    today: today,
                    todayDate: todayDate
                )
            case (.some, .none):
                if direction == .appleToSkylight {
                    actions.append(.createRemote(appleID: link.appleID))
                } else {
                    actions.append(.deleteApple(appleID: link.appleID))
                }
            case (.none, .some):
                if direction == .skylightToApple {
                    actions.append(.createApple(seriesID: link.skylightID))
                } else {
                    actions.append(.deleteRemote(seriesID: link.skylightID))
                }
            case (.none, .none):
                break
            }
        }

        if direction != .skylightToApple {
            actions += apple.filter { !linkedApple.contains($0.id) }.map {
                .createRemote(appleID: $0.id)
            }
        }
        if direction != .appleToSkylight {
            actions += skylight.filter { !linkedRemote.contains($0.id) }.map {
                .createApple(seriesID: $0.id)
            }
        }
        return actions.sorted { $0.sortKey < $1.sortKey }
    }

    private static func pairActions(
        apple: ChoreReminderSnapshot,
        remote: SkylightChoreSnapshot,
        link: ChoreSyncLink,
        direction: ReminderSyncDirection,
        policy: SyncConflictPolicy,
        today: String,
        todayDate: Date
    ) -> [ChoreSyncAction] {
        var result: [ChoreSyncAction] = []
        let appleChanged = apple.modifiedAt.isMeaningfullyAfter(link.lastAppleModifiedAt)
        let remoteChanged = remote.modifiedAt.isMeaningfullyAfter(link.lastSkylightModifiedAt)
        let appleContentChanged = apple.title != (link.baselineTitle ?? remote.title)
            || apple.notes != link.baselineNotes
            || (!link.recurrenceDegraded && canonical(apple.recurrence) != link.baselineRecurrence)
            || apple.memberKey != link.memberKey
        let remoteContentChanged = remote.title != (link.baselineTitle ?? apple.title)
            || remote.notes != link.baselineNotes
            || (!link.recurrenceDegraded && canonical(remote.recurrence) != link.baselineRecurrence)
            || remote.memberKey != link.memberKey

        if appleContentChanged || remoteContentChanged {
            switch direction {
            case .appleToSkylight:
                if appleContentChanged { result.append(.updateRemote(appleID: apple.id, seriesID: remote.id)) }
            case .skylightToApple:
                if remoteContentChanged { result.append(.updateApple(appleID: apple.id, seriesID: remote.id)) }
            case .twoWay:
                switch (appleContentChanged, remoteContentChanged) {
                case (true, false): result.append(.updateRemote(appleID: apple.id, seriesID: remote.id))
                case (false, true): result.append(.updateApple(appleID: apple.id, seriesID: remote.id))
                case (true, true):
                    let appleWins = switch policy {
                    case .appleWins: true
                    case .skylightWins: false
                    case .newestWins: appleChanged && (!remoteChanged || apple.modifiedAt >= remote.modifiedAt)
                    }
                    result.append(appleWins
                        ? .updateRemote(appleID: apple.id, seriesID: remote.id)
                        : .updateApple(appleID: apple.id, seriesID: remote.id))
               case (false, false): break
               }
           }
       }

        // When a recurring chore rolls to a new day without being completed on
        // either side, Skylight advances the occurrence's start date but the
        // Apple reminder keeps its old due date. The content-change checks
        // above don't cover the due date, so the Apple reminder would stay
        // stale. Detect the drift and push an update so the Apple reminder
        // reflects the current day.
        if !appleContentChanged, !remoteContentChanged,
           direction != .appleToSkylight,
           let remoteStart = remote.startDate,
           let appleDue = apple.dueDate,
           appleDue < remoteStart,
           !Calendar.current.isDate(appleDue, inSameDayAs: remoteStart) {
            result.append(.updateApple(appleID: apple.id, seriesID: remote.id))
        }

        let remoteCompleted = remote.todayStatus == .complete || remote.todayStatus == .skipped
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: todayDate) ?? .distantFuture
        // A rolled-forward due date signals completion only for a genuinely
        // recurring chore (EventKit spawns the next occurrence), including a
        // degraded rule it still advances. Postponing a one-off chore is a
        // reschedule, not a completion.
        let rollsOccurrenceForward = apple.recurrence != nil || apple.recurrenceUnsupported
        let appleRolledForward = if rollsOccurrenceForward,
                                     let baseline = link.baselineDueDate,
                                     let due = apple.dueDate {
            due > baseline && baseline < tomorrow
        } else {
            false
        }
        let appleCompleted = apple.isCompleted || appleRolledForward
        let alreadyCompleted = link.baselineCompletedInstanceDate == today

        if remoteCompleted == appleCompleted {
            return result
        }
        if alreadyCompleted {
            if remoteCompleted, !appleCompleted, direction != .skylightToApple {
                result.append(.completeRemote(seriesID: remote.id, status: .pending))
            } else if !remoteCompleted, appleCompleted, direction != .appleToSkylight {
                result.append(.completeApple(appleID: apple.id, completed: false))
            }
        } else if remoteCompleted, direction != .appleToSkylight {
            result.append(.completeApple(appleID: apple.id, completed: true))
        } else if appleCompleted, direction != .skylightToApple {
            result.append(.completeRemote(seriesID: remote.id, status: .complete))
        }
        return result
    }

    private static func key(_ title: String, _ memberKey: String) -> String {
        "\(title.trimmed.lowercased())\u{0}\(memberKey)"
    }

    private static func canonical(_ recurrence: ParsedRecurrenceRule?) -> String? {
        recurrence.map(RecurrenceRuleConverter.format)
    }
}

private extension ChoreSyncAction {
    var sortKey: String {
        switch self {
        case let .createRemote(id): "0:\(id)"
        case let .createApple(id): "1:\(id)"
        case let .updateRemote(appleID, remoteID): "2:\(appleID):\(remoteID)"
        case let .updateApple(appleID, remoteID): "3:\(appleID):\(remoteID)"
        case let .completeRemote(id, status): "4:\(id):\(status.rawValue)"
        case let .completeApple(id, completed): "5:\(id):\(completed)"
        case let .deleteRemote(id): "6:\(id)"
        case let .deleteApple(id): "7:\(id)"
        }
    }
}
