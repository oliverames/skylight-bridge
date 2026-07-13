struct SkylightCalendarEventAttributes: Codable, Equatable, Sendable {
    let summary: String?
    let description: String?
    let startsAt: String?
    let endsAt: String?
    let allDay: Bool?
    let color: String?
    let location: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
        case color
        case location
        case timezone
    }
}

struct SkylightCalendarEventRequest: Codable, Equatable, Sendable {
    let summary: String
    let description: String?
    let startsAt: String?
    let endsAt: String?
    let allDay: Bool?
    let categoryIDs: [String]?
    let eventType: String?
    let rrule: [String]?
    let invitedEmails: [String]?
    let location: String?
    let timezone: String?
    let countdownEnabled: Bool?

    init(
        summary: String,
        description: String? = nil,
        startsAt: String? = nil,
        endsAt: String? = nil,
        allDay: Bool? = nil,
        categoryIDs: [String]? = nil,
        eventType: String? = nil,
        rrule: [String]? = nil,
        invitedEmails: [String]? = nil,
        location: String? = nil,
        timezone: String? = nil,
        countdownEnabled: Bool? = nil
    ) {
        self.summary = summary
        self.description = description
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.categoryIDs = categoryIDs
        self.eventType = eventType
        self.rrule = rrule
        self.invitedEmails = invitedEmails
        self.location = location
        self.timezone = timezone
        self.countdownEnabled = countdownEnabled
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
        case categoryIDs = "category_ids"
        case eventType = "event_type"
        case rrule
        case invitedEmails = "invited_emails"
        case location
        case timezone
        case countdownEnabled = "countdown_enabled"
    }
}

struct SkylightCalendarAccountAttributes: Codable, Equatable, Sendable {
    let label: String?
    let kind: String?
    let email: String?
    let enabled: Bool?
}

struct SkylightSourceCalendarAttributes: Codable, Equatable, Sendable {
    let label: String?
    let kind: String?
    let editable: Bool?
    let enabled: Bool?
    let color: String?
}

struct SkylightSourceCalendarRequest: Codable, Equatable, Sendable {
    let label: String?
    let kind: String?
    let enabled: Bool?
    let color: String?
    let url: String?

    init(
        label: String? = nil,
        kind: String? = nil,
        enabled: Bool? = nil,
        color: String? = nil,
        url: String? = nil
    ) {
        self.label = label
        self.kind = kind
        self.enabled = enabled
        self.color = color
        self.url = url
    }
}

struct SkylightStringListResponse: Codable, Equatable, Sendable {
    let data: [String]
}
