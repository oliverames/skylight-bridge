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
    var acknowledgedAdvanceDueDate: Date? = nil
}

struct ChoreAdoptionPair: Equatable, Sendable {
    let appleID: String
    let skylightID: String
}

/// How a chore mapping should be torn down when the user disables Chore Chart
/// sync. Each mode names the side to *keep*; the other side's items are removed,
/// and the auto-created Apple lists go with the Apple side.
enum ChoreTeardownMode: String, CaseIterable, Sendable {
    case keepSkylight
    case keepReminders
    case removeEverything

    var removesSkylight: Bool { self != .keepSkylight }
    var removesAppleReminders: Bool { self != .keepReminders }
}

struct ChoreTeardownResult: Equatable, Sendable {
    var skylightItemsRemoved = 0
    var appleItemsRemoved = 0
    var listsRemoved = 0
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
