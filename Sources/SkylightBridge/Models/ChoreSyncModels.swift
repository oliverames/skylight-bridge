import Foundation

struct ChoreReminderSnapshot: Equatable, Sendable {
    let id: String
    let listID: String
    let memberKey: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let dueDate: Date?
    let recurrence: ParsedRecurrenceRule?
    let recurrenceUnsupported: Bool
    let modifiedAt: Date
}

struct ChoreReminderDraft: Sendable {
    let title: String
    let notes: String?
    let dueDate: Date?
    let recurrence: ParsedRecurrenceRule?
}

struct ChoreReminderPatch: Sendable {
    let title: String
    let notes: String?
    let dueDate: Date?
    let recurrence: ParsedRecurrenceRule?
    let replaceRecurrence: Bool
}

struct SkylightChoreSnapshot: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let memberKey: String
    let recurrenceRaw: [String]
    let recurrence: ParsedRecurrenceRule?
    let recurrenceUnsupported: Bool
    let todayStatus: SkylightChoreStatus?
    let startDate: Date?
    let modifiedAt: Date
}

struct ChoreSyncLink: Equatable, Sendable {
    let appleID: String
    let skylightID: String
    let memberKey: String
    let lastAppleModifiedAt: Date
    let lastSkylightModifiedAt: Date
    let baselineTitle: String?
    let baselineNotes: String?
    let baselineRecurrence: String?
    let baselineDueDate: Date?
    let baselineCompletedInstanceDate: String?
    let recurrenceDegraded: Bool
}

struct ChoreAdoptionPair: Equatable, Sendable {
    let appleID: String
    let skylightID: String
}

enum ChoreSyncAction: Equatable, Sendable {
    case createRemote(appleID: String)
    case createApple(seriesID: String)
    case updateRemote(appleID: String, seriesID: String)
    case updateApple(appleID: String, seriesID: String)
    case completeRemote(seriesID: String, status: SkylightChoreStatus)
    case completeApple(appleID: String, completed: Bool)
    case deleteRemote(seriesID: String)
    case deleteApple(appleID: String)
}
