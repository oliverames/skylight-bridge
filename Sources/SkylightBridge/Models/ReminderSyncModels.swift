import Foundation

struct ReminderSnapshot: Equatable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let modifiedAt: Date
}

struct SkylightListItemSnapshot: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let modifiedAt: Date
}

struct ReminderSyncLink: Equatable, Sendable {
    let appleID: String
    let skylightID: String
    let lastAppleModifiedAt: Date
    let lastSkylightModifiedAt: Date
    // Last-synced field values, used to merge two-way edits field by field.
    // Nil for records written before field-level merge existed.
    let baselineTitle: String?
    let baselineCompleted: Bool?
}

enum ReminderSyncDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case appleToSkylight
    case skylightToApple
    case twoWay
}

enum ReminderMappingCleanupSide: String, CaseIterable, Sendable {
    case skylight
    case appleReminders
    case none
}

enum SyncConflictPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case newestWins
    case appleWins
    case skylightWins

    var label: String {
        switch self {
        case .newestWins: "Newest change wins"
        case .appleWins: "Apple wins"
        case .skylightWins: "Skylight wins"
        }
    }
}

enum ReminderSyncAction: Equatable, Sendable {
    case createRemote(appleID: String)
    case createApple(remoteID: String)
    case updateRemote(appleID: String, remoteID: String)
    case updateApple(appleID: String, remoteID: String)
    // A two-way edit merged field by field, written to both sides.
    case merge(appleID: String, remoteID: String, title: String, isCompleted: Bool)
    case deleteRemote(remoteID: String)
    case deleteApple(appleID: String)
}
