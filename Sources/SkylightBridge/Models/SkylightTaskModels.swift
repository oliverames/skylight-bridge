enum SkylightChoreStatus: String, Codable, Equatable, Sendable {
    case pending
    case complete
    case skipped
}

struct SkylightChoreAttributes: Codable, Equatable, Sendable {
    let summary: String?
    let description: String?
    let group: String?
    let status: SkylightChoreStatus?
    let start: String?
    let startTime: String?
    let completedOn: String?
    let rewardPoints: Int?
    let recurring: Bool?
    let recurringUntil: String?
    let recurrenceSet: [String]?
    let upForGrabs: Bool?
    let emojiIcon: String?
    let routine: Bool?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case group
        case status
        case start
        case startTime = "start_time"
        case completedOn = "completed_on"
        case rewardPoints = "reward_points"
        case recurring
        case recurringUntil = "recurring_until"
        case recurrenceSet = "recurrence_set"
        case upForGrabs = "up_for_grabs"
        case emojiIcon = "emoji_icon"
        case routine
        case position
    }
}

struct SkylightChoreRequest: Codable, Equatable, Sendable {
    let summary: String?
    let description: String?
    let start: String?
    let startTime: String?
    let rewardPoints: Int?
    let status: SkylightChoreStatus?
    let categoryID: String?
    let categoryIDs: [String]?
    let recurring: Bool?
    let recurrenceSet: [String]?
    let recurringUntil: String?
    let upForGrabs: Bool?
    let emojiIcon: String?
    let routine: Bool?
    let position: Int?

    init(
        summary: String? = nil,
        description: String? = nil,
        start: String? = nil,
        startTime: String? = nil,
        rewardPoints: Int? = nil,
        status: SkylightChoreStatus? = nil,
        categoryID: String? = nil,
        categoryIDs: [String]? = nil,
        recurring: Bool? = nil,
        recurrenceSet: [String]? = nil,
        recurringUntil: String? = nil,
        upForGrabs: Bool? = nil,
        emojiIcon: String? = nil,
        routine: Bool? = nil,
        position: Int? = nil
    ) {
        self.summary = summary
        self.description = description
        self.start = start
        self.startTime = startTime
        self.rewardPoints = rewardPoints
        self.status = status
        self.categoryID = categoryID
        self.categoryIDs = categoryIDs
        self.recurring = recurring
        self.recurrenceSet = recurrenceSet
        self.recurringUntil = recurringUntil
        self.upForGrabs = upForGrabs
        self.emojiIcon = emojiIcon
        self.routine = routine
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case start
        case startTime = "start_time"
        case rewardPoints = "reward_points"
        case status
        case categoryID = "category_id"
        case categoryIDs = "category_ids"
        case recurring
        case recurrenceSet = "recurrence_set"
        case recurringUntil = "recurring_until"
        case upForGrabs = "up_for_grabs"
        case emojiIcon = "emoji_icon"
        case routine
        case position
    }
}

struct SkylightChoreBatchRequest: Codable, Equatable, Sendable {
    let chores: [SkylightChoreRequest]
}

struct SkylightChoreCompletionRequest: Codable, Equatable, Sendable {
    let status: SkylightChoreStatus
    let instanceDate: String?
    let instanceTime: String?
    let categoryID: String?
    let completedOn: String?

    init(
        status: SkylightChoreStatus,
        instanceDate: String? = nil,
        instanceTime: String? = nil,
        categoryID: String? = nil,
        completedOn: String? = nil
    ) {
        self.status = status
        self.instanceDate = instanceDate
        self.instanceTime = instanceTime
        self.categoryID = categoryID
        self.completedOn = completedOn
    }

    enum CodingKeys: String, CodingKey {
        case status
        case instanceDate = "instance_date"
        case instanceTime = "instance_time"
        case categoryID = "category_id"
        case completedOn = "completed_on"
    }
}

struct SkylightChoreMovePosition: Codable, Equatable, Sendable {
    let before: String?
    let after: String?
}

struct SkylightChoreMoveRequest: Codable, Equatable, Sendable {
    let position: SkylightChoreMovePosition
}

struct SkylightTaskBoxItemAttributes: Codable, Equatable, Sendable {
    let title: String?
    let completed: Bool?
    let position: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case completed
        case position
        case createdAt = "created_at"
    }
}

struct SkylightTaskBoxItemRequest: Codable, Equatable, Sendable {
    let title: String?
    let completed: Bool?
    let position: Int?

    init(title: String? = nil, completed: Bool? = nil, position: Int? = nil) {
        self.title = title
        self.completed = completed
        self.position = position
    }
}

struct SkylightRewardAttributes: Codable, Equatable, Sendable {
    let name: String?
    let pointValue: Int?
    let description: String?
    let emojiIcon: String?
    let respawnOnRedemption: Bool?
    let redeemedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case pointValue = "point_value"
        case description
        case emojiIcon = "emoji_icon"
        case respawnOnRedemption = "respawn_on_redemption"
        case redeemedAt = "redeemed_at"
    }
}

struct SkylightRewardRequest: Codable, Equatable, Sendable {
    let name: String?
    let pointValue: Int?
    let description: String?
    let emojiIcon: String?
    let respawnOnRedemption: Bool?
    let categoryIDs: [Int]?

    init(
        name: String? = nil,
        pointValue: Int? = nil,
        description: String? = nil,
        emojiIcon: String? = nil,
        respawnOnRedemption: Bool? = nil,
        categoryIDs: [Int]? = nil
    ) {
        self.name = name
        self.pointValue = pointValue
        self.description = description
        self.emojiIcon = emojiIcon
        self.respawnOnRedemption = respawnOnRedemption
        self.categoryIDs = categoryIDs
    }

    enum CodingKeys: String, CodingKey {
        case name
        case pointValue = "point_value"
        case description
        case emojiIcon = "emoji_icon"
        case respawnOnRedemption = "respawn_on_redemption"
        case categoryIDs = "category_ids"
    }
}

struct SkylightRewardPoint: Codable, Equatable, Sendable {
    let categoryID: Int
    let currentPointBalance: Int

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case currentPointBalance = "current_point_balance"
    }
}

struct SkylightRewardPointAdjustment: Codable, Equatable, Sendable {
    let categoryIDs: [Int]
    let points: Int

    enum CodingKeys: String, CodingKey {
        case categoryIDs = "category_ids"
        case points
    }
}
