@preconcurrency import EventKit
import Foundation

enum AppleRemindersStoreError: Error, LocalizedError, Sendable {
    case accessDenied
    case listNotFound(String)
    case reminderNotFound(String)
    case readOnlyList(String)
    case invalidTitle
    case invalidColor
    case noListUpdate
    case invalidPriority(Int)
    case noWritableSource
    case eventKit(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Full Apple Reminders access is not authorized."
        case let .listNotFound(identifier):
            "Apple Reminders list \(identifier) was not found."
        case let .reminderNotFound(identifier):
            "Apple Reminder \(identifier) was not found."
        case let .readOnlyList(identifier):
            "Apple Reminders list \(identifier) does not allow changes."
        case .invalidTitle:
            "A reminder title cannot be empty."
        case .invalidColor:
            "A reminder-list color must be a six-digit hex value."
        case .noListUpdate:
            "A reminder-list update needs a title or color."
        case let .invalidPriority(priority):
            "Reminder priority \(priority) is outside the supported range of 0 through 9."
        case .noWritableSource:
            "No Reminders account accepts new lists on this Mac."
        case let .eventKit(message):
            "EventKit operation failed: \(message)"
        }
    }
}

@MainActor
final class AppleRemindersStore {
    private let eventStore: EKEventStore
    private let choreCalendar: Calendar

    init(
        eventStore: EKEventStore = EKEventStore(),
        choreCalendar: Calendar = .current
    ) {
        self.eventStore = eventStore
        var choreCalendar = choreCalendar
        choreCalendar.locale = Locale(identifier: "en_US_POSIX")
        self.choreCalendar = choreCalendar
    }

    func authorizationStatus() -> AppleRemindersAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .fullAccess:
            .fullAccess
        case .writeOnly:
            .writeOnly
        @unknown default:
            .unknown
        }
    }

    func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func lists() throws -> [AppleReminderListSnapshot] {
        try requireFullAccess()
        return eventStore.calendars(for: .reminder)
            .map {
                AppleReminderListSnapshot(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    colorHex: ReminderListColor.hex(for: $0.cgColor),
                    sourceID: $0.source.sourceIdentifier,
                    sourceTitle: $0.source.title,
                    allowsContentModifications: $0.allowsContentModifications
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func reminderList(withID listID: String) throws -> AppleReminderListSnapshot {
        try requireFullAccess()
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder) else {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        return AppleReminderListSnapshot(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: ReminderListColor.hex(for: calendar.cgColor),
            sourceID: calendar.source.sourceIdentifier,
            sourceTitle: calendar.source.title,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    @discardableResult
    func updateReminderList(
        withID listID: String,
        title: String? = nil,
        colorHex: String? = nil
    ) throws -> AppleReminderListSnapshot {
        try requireFullAccess()
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != "" else {
            throw AppleRemindersStoreError.invalidTitle
        }
        guard name != nil || colorHex != nil else {
            throw AppleRemindersStoreError.noListUpdate
        }
        if let colorHex, ReminderListColor.cgColor(for: colorHex) == nil {
            throw AppleRemindersStoreError.invalidColor
        }
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder) else {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        guard calendar.allowsContentModifications else {
            throw AppleRemindersStoreError.readOnlyList(listID)
        }
        if let name {
            calendar.title = name
        }
        if let colorHex, let color = ReminderListColor.cgColor(for: colorHex) {
            calendar.cgColor = color
        }
        do {
            try eventStore.saveCalendar(calendar, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return AppleReminderListSnapshot(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: ReminderListColor.hex(for: calendar.cgColor),
            sourceID: calendar.source.sourceIdentifier,
            sourceTitle: calendar.source.title,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    @discardableResult
    func createList(named title: String) throws -> AppleReminderListSnapshot {
        try requireFullAccess()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppleRemindersStoreError.invalidTitle
        }
        guard let source = preferredListSource() else {
            throw AppleRemindersStoreError.noWritableSource
        }

        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = name
        calendar.source = source

        do {
            try eventStore.saveCalendar(calendar, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return AppleReminderListSnapshot(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: ReminderListColor.hex(for: calendar.cgColor),
            sourceID: source.sourceIdentifier,
            sourceTitle: source.title,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    /// Compensates only a list created moments earlier by the mapping editor
    /// when its local configuration write fails. No reminder can be added
    /// between the synchronous create and rollback calls.
    func deleteNewlyCreatedList(withID listID: String) throws {
        try requireFullAccess()
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder),
              calendar.allowsContentModifications else {
            return
        }
        do {
            try eventStore.removeCalendar(calendar, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
    }

    /// Removes an auto-created chore list, but only when it holds no reminders,
    /// so a list the user has repurposed is never deleted out from under them.
    /// Returns whether the list was actually removed.
    @discardableResult
    func deleteListIfEmpty(withID listID: String) async throws -> Bool {
        try requireFullAccess()
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder),
              calendar.allowsContentModifications else {
            return false
        }
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let isEmpty: Bool = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).isEmpty)
            }
        }
        guard isEmpty else { return false }
        do {
            try eventStore.removeCalendar(calendar, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return true
    }

    private func preferredListSource() -> EKSource? {
        if let source = eventStore.defaultCalendarForNewReminders()?.source {
            return source
        }
        let sources = eventStore.sources
        return sources.first { $0.sourceType == .calDAV }
            ?? sources.first { $0.sourceType == .local }
    }

    func reminders(in listID: String) async throws -> [AppleReminderSnapshot] {
        try requireFullAccess()
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder) else {
            throw AppleRemindersStoreError.listNotFound(listID)
        }

        let predicate = eventStore.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                Task { @MainActor in
                    continuation.resume(returning: Self.snapshots(for: reminders ?? []))
                }
            }
        }
    }

    func choreReminders(in listID: String, memberKey: String) async throws -> [ChoreReminderSnapshot] {
        try requireFullAccess()
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder) else {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        let predicate = eventStore.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                Task { @MainActor in
                    continuation.resume(returning: (reminders ?? []).map {
                        Self.choreSnapshot(
                            for: $0,
                            memberKey: memberKey,
                            calendar: self.choreCalendar
                        )
                    })
                }
            }
        }
    }

    func createChoreReminder(
        in listID: String,
        draft: ChoreReminderDraft,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try requireFullAccess()
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder) else {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        guard calendar.allowsContentModifications else {
            throw AppleRemindersStoreError.readOnlyList(listID)
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.dueDateComponents = draft.dueDate.map {
            Self.choreDateComponents($0, calendar: choreCalendar)
        }
        if let recurrence = draft.recurrence {
            reminder.addRecurrenceRule(RecurrenceRuleConverter.ekRecurrenceRule(from: recurrence))
        }
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return Self.choreSnapshot(
            for: reminder,
            memberKey: memberKey,
            calendar: choreCalendar
        )
    }

    func updateChoreReminder(
        withID reminderID: String,
        patch: ChoreReminderPatch,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try requireFullAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AppleRemindersStoreError.reminderNotFound(reminderID)
        }
        reminder.title = patch.title
        reminder.notes = patch.notes
        reminder.dueDateComponents = patch.dueDate.map {
            Self.choreDateComponents($0, calendar: choreCalendar)
        }
        if patch.replaceRecurrence {
            for rule in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(rule) }
            if let recurrence = patch.recurrence {
                reminder.addRecurrenceRule(RecurrenceRuleConverter.ekRecurrenceRule(from: recurrence))
            }
        }
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return Self.choreSnapshot(
            for: reminder,
            memberKey: memberKey,
            calendar: choreCalendar
        )
    }

    func setChoreReminderCompletion(
        withID reminderID: String,
        completed: Bool,
        dueDate: Date?,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try requireFullAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AppleRemindersStoreError.reminderNotFound(reminderID)
        }
        if !completed, let dueDate {
            reminder.dueDateComponents = Self.choreDateComponents(
                dueDate,
                calendar: choreCalendar
            )
        }
        reminder.isCompleted = completed
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return Self.choreSnapshot(
            for: reminder,
            memberKey: memberKey,
            calendar: choreCalendar
        )
    }

    func moveChoreReminder(
        withID reminderID: String,
        toListID listID: String,
        memberKey: String
    ) throws -> ChoreReminderSnapshot {
        try requireFullAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AppleRemindersStoreError.reminderNotFound(reminderID)
        }
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder) else {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        reminder.calendar = calendar
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return Self.choreSnapshot(
            for: reminder,
            memberKey: memberKey,
            calendar: choreCalendar
        )
    }

    func reminder(withID reminderID: String) throws -> AppleReminderSnapshot {
        try requireFullAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AppleRemindersStoreError.reminderNotFound(reminderID)
        }
        return Self.snapshot(for: reminder)
    }

    @discardableResult
    func createReminder(
        in listID: String,
        draft: AppleReminderDraft
    ) throws -> AppleReminderSnapshot {
        try requireFullAccess()
        try validate(title: draft.title, priority: draft.priority)
        guard let calendar = eventStore.calendar(withIdentifier: listID),
              calendar.allowedEntityTypes.contains(.reminder) else {
            throw AppleRemindersStoreError.listNotFound(listID)
        }
        guard calendar.allowsContentModifications else {
            throw AppleRemindersStoreError.readOnlyList(listID)
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.url = draft.url
        reminder.startDateComponents = normalized(draft.startDateComponents)
        reminder.dueDateComponents = normalized(draft.dueDateComponents)
        reminder.priority = draft.priority
        reminder.isCompleted = draft.isCompleted

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return Self.snapshot(for: reminder)
    }

    @discardableResult
    func updateReminder(
        withID reminderID: String,
        patch: AppleReminderPatch
    ) throws -> AppleReminderSnapshot {
        try requireFullAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AppleRemindersStoreError.reminderNotFound(reminderID)
        }
        guard reminder.calendar.allowsContentModifications else {
            throw AppleRemindersStoreError.readOnlyList(reminder.calendar.calendarIdentifier)
        }

        if let title = patch.title {
            try validate(title: title, priority: patch.priority ?? reminder.priority)
            reminder.title = title
        } else if let priority = patch.priority {
            try validate(title: reminder.title, priority: priority)
        }

        apply(patch.notes, to: &reminder.notes)
        apply(patch.url, to: &reminder.url)

        switch patch.startDateComponents {
        case .unchanged:
            break
        case let .set(value):
            reminder.startDateComponents = normalized(value)
        case .clear:
            reminder.startDateComponents = nil
        }
        switch patch.dueDateComponents {
        case .unchanged:
            break
        case let .set(value):
            reminder.dueDateComponents = normalized(value)
        case .clear:
            reminder.dueDateComponents = nil
        }

        if let priority = patch.priority {
            reminder.priority = priority
        }
        if let isCompleted = patch.isCompleted {
            reminder.isCompleted = isCompleted
        }

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
        return Self.snapshot(for: reminder)
    }

    func removeReminder(withID reminderID: String) throws {
        try requireFullAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw AppleRemindersStoreError.reminderNotFound(reminderID)
        }
        guard reminder.calendar.allowsContentModifications else {
            throw AppleRemindersStoreError.readOnlyList(reminder.calendar.calendarIdentifier)
        }

        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw AppleRemindersStoreError.eventKit(error.localizedDescription)
        }
    }

    private func requireFullAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw AppleRemindersStoreError.accessDenied
        }
    }

    private func validate(title: String, priority: Int) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppleRemindersStoreError.invalidTitle
        }
        guard (0 ... 9).contains(priority) else {
            throw AppleRemindersStoreError.invalidPriority(priority)
        }
    }

    private func normalized(_ dateComponents: DateComponents?) -> DateComponents? {
        guard var dateComponents else {
            return nil
        }
        dateComponents.calendar = Calendar(identifier: .gregorian)
        return dateComponents
    }

    private func apply<Value>(
        _ update: AppleNullableUpdate<Value>,
        to value: inout Value?
    ) {
        switch update {
        case .unchanged:
            break
        case let .set(newValue):
            value = newValue
        case .clear:
            value = nil
        }
    }

    nonisolated private static func snapshot(for reminder: EKReminder) -> AppleReminderSnapshot {
        AppleReminderSnapshot(
            id: reminder.calendarItemIdentifier,
            externalID: reminder.calendarItemExternalIdentifier,
            listID: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title,
            title: reminder.title,
            notes: reminder.notes,
            url: reminder.url,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            startDateComponents: reminder.startDateComponents,
            dueDateComponents: reminder.dueDateComponents,
            priority: reminder.priority,
            creationDate: reminder.creationDate,
            modificationDate: reminder.lastModifiedDate,
            hasRecurrenceRules: reminder.hasRecurrenceRules
        )
    }

    nonisolated private static func snapshots(
        for reminders: [EKReminder]
    ) -> [AppleReminderSnapshot] {
        reminders
            .map(snapshot(for:))
            .sorted { left, right in
                left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
    }

    nonisolated private static func choreSnapshot(
        for reminder: EKReminder,
        memberKey: String,
        calendar: Calendar
    ) -> ChoreReminderSnapshot {
        let parsedRecurrence: ParsedRecurrenceRule?
        let recurrenceUnsupported: Bool
        let recurrenceRules = reminder.recurrenceRules ?? []
        if recurrenceRules.count > 1 {
            // Skylight accepts one recurrence rule. Combining EventKit rules
            // would silently narrow the user's schedule to the first rule.
            parsedRecurrence = nil
            recurrenceUnsupported = true
        } else if let first = recurrenceRules.first {
            do {
                parsedRecurrence = try RecurrenceRuleConverter.parsedRule(from: first)
                recurrenceUnsupported = false
            } catch {
                parsedRecurrence = nil
                recurrenceUnsupported = true
            }
        } else {
            parsedRecurrence = nil
            recurrenceUnsupported = false
        }
        return ChoreReminderSnapshot(
            id: reminder.calendarItemIdentifier,
            listID: reminder.calendar.calendarIdentifier,
            memberKey: memberKey,
            title: reminder.title,
            notes: reminder.notes,
            isCompleted: reminder.isCompleted,
            dueDate: reminder.dueDateComponents.flatMap {
                choreDate(from: $0, calendar: calendar)
            },
            recurrence: parsedRecurrence,
            recurrenceUnsupported: recurrenceUnsupported,
            modifiedAt: reminder.lastModifiedDate ?? reminder.creationDate ?? .distantPast
        )
    }

    nonisolated static func choreDate(
        from sourceComponents: DateComponents,
        calendar: Calendar
    ) -> Date? {
        var components = sourceComponents
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)
    }

    nonisolated static func choreDateComponents(
        _ date: Date,
        calendar: Calendar
    ) -> DateComponents {
        let includeTime = calendar.component(.hour, from: date) != 0
            || calendar.component(.minute, from: date) != 0
        var components = calendar.dateComponents(
            includeTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}
