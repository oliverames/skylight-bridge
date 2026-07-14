@preconcurrency import EventKit
import Foundation

enum AppleRemindersStoreError: Error, LocalizedError, Sendable {
    case accessDenied
    case listNotFound(String)
    case reminderNotFound(String)
    case readOnlyList(String)
    case invalidTitle
    case invalidPriority(Int)
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
        case let .invalidPriority(priority):
            "Reminder priority \(priority) is outside the supported range of 0 through 9."
        case let .eventKit(message):
            "EventKit operation failed: \(message)"
        }
    }
}

@MainActor
final class AppleRemindersStore {
    private let eventStore: EKEventStore
    private var changeContinuation: AsyncStream<AppleSourceChange>.Continuation?
    private var notificationToken: (any NSObjectProtocol)?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
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
                    sourceID: $0.source.sourceIdentifier,
                    sourceTitle: $0.source.title,
                    allowsContentModifications: $0.allowsContentModifications
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
                continuation.resume(returning: Self.snapshots(for: reminders ?? []))
            }
        }
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

    func changes() -> AsyncStream<AppleSourceChange> {
        if notificationToken == nil {
            notificationToken = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: eventStore,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.changeContinuation?.yield(AppleSourceChange(occurredAt: Date()))
                }
            }
        }

        return AsyncStream { continuation in
            self.changeContinuation?.finish()
            self.changeContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stopObservingChanges()
                }
            }
        }
    }

    func stopObservingChanges() {
        changeContinuation?.finish()
        changeContinuation = nil
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
            self.notificationToken = nil
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
}
