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
}

enum ReminderSyncDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case appleToSkylight
    case skylightToApple
    case twoWay
}

enum ReminderConflictPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case newestWins
    case appleWins
    case skylightWins
}

enum ReminderSyncAction: Equatable, Sendable {
    case createRemote(appleID: String)
    case createApple(remoteID: String)
    case updateRemote(appleID: String, remoteID: String)
    case updateApple(appleID: String, remoteID: String)
    case deleteRemote(remoteID: String)
    case deleteApple(appleID: String)
}
