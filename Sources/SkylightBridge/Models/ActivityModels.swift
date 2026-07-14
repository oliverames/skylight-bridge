import Foundation

enum ActivityLevel: String, Codable, Sendable {
    case info
    case success
    case warning
    case error
}

enum IntegrationArea: String, Codable, Sendable {
    case photos
    case reminders
    case recipes
    case meals
    case account
    case system
}

struct ActivityEntry: Identifiable, Codable, Sendable, Hashable {
    private static let maximumMessageCharacters = 1_000
    let id: UUID
    let date: Date
    let level: ActivityLevel
    let area: IntegrationArea
    let message: String
    let isDryRun: Bool

    init(
        id: UUID = UUID(),
        date: Date = .now,
        level: ActivityLevel,
        area: IntegrationArea,
        message: String,
        isDryRun: Bool = false
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.area = area
        self.message = String(message.prefix(Self.maximumMessageCharacters))
        self.isDryRun = isDryRun
    }
}
