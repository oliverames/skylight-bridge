enum SkylightChoreStatus: String, Codable, Equatable, Sendable {
    case pending
    case complete
    case skipped
}

/// Decodes string-keyed enums leniently: a server-added value decodes as nil
/// ("no information") instead of failing the whole collection response, per
/// the compatibility policy in docs/API_EVIDENCE.md. Request-side structs keep
/// the strict enums so the bridge never sends an unknown value.
enum TolerantDecoding {
    static func enumValue<E: RawRepresentable, K: CodingKey>(
        _ type: E.Type,
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> E? where E.RawValue == String {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return E(rawValue: raw)
    }
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
    let series: String?

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
        case series
    }

    init(
        summary: String? = nil,
        description: String? = nil,
        group: String? = nil,
        status: SkylightChoreStatus? = nil,
        start: String? = nil,
        startTime: String? = nil,
        completedOn: String? = nil,
        rewardPoints: Int? = nil,
        recurring: Bool? = nil,
        recurringUntil: String? = nil,
        recurrenceSet: [String]? = nil,
        upForGrabs: Bool? = nil,
        emojiIcon: String? = nil,
        routine: Bool? = nil,
        position: Int? = nil,
        series: String? = nil
    ) {
        self.summary = summary
        self.description = description
        self.group = group
        self.status = status
        self.start = start
        self.startTime = startTime
        self.completedOn = completedOn
        self.rewardPoints = rewardPoints
        self.recurring = recurring
        self.recurringUntil = recurringUntil
        self.recurrenceSet = recurrenceSet
        self.upForGrabs = upForGrabs
        self.emojiIcon = emojiIcon
        self.routine = routine
        self.position = position
        self.series = series
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        status = try TolerantDecoding.enumValue(
            SkylightChoreStatus.self, from: container, forKey: .status
        )
        start = try container.decodeIfPresent(String.self, forKey: .start)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        completedOn = try container.decodeIfPresent(String.self, forKey: .completedOn)
        rewardPoints = try container.decodeIfPresent(Int.self, forKey: .rewardPoints)
        recurring = try container.decodeIfPresent(Bool.self, forKey: .recurring)
        recurringUntil = try container.decodeIfPresent(String.self, forKey: .recurringUntil)
        recurrenceSet = try container.decodeIfPresent([String].self, forKey: .recurrenceSet)
        upForGrabs = try container.decodeIfPresent(Bool.self, forKey: .upForGrabs)
        emojiIcon = try container.decodeIfPresent(String.self, forKey: .emojiIcon)
        routine = try container.decodeIfPresent(Bool.self, forKey: .routine)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
        series = try container.decodeIfPresent(String.self, forKey: .series)
    }
}

/// `/chores/all` is grouped by task kind and time bucket rather than using the
/// normal top-level JSON:API collection envelope. Each leaf is a regular
/// collection response. Keep the dictionary keys open so a server-added bucket
/// does not break decoding.
struct SkylightAllChoresResponse: Codable, Equatable, Sendable {
    let chores: [String: SkylightCollectionResponse<SkylightChoreAttributes>]
    let routines: [String: SkylightCollectionResponse<SkylightChoreAttributes>]

    var data: [SkylightResource<SkylightChoreAttributes>] {
        let resources = [chores, routines].flatMap { group in
            group.keys.sorted(by: Self.bucketComesFirst).flatMap { group[$0]?.data ?? [] }
        }
        var seen: Set<String> = []
        return resources.filter { resource in
            let identity = resource.attributes.series ?? resource.id
            return seen.insert(identity).inserted
        }
    }

    private static func bucketComesFirst(_ lhs: String, _ rhs: String) -> Bool {
        let priority = ["today": 0, "late": 1, "future": 2]
        let left = priority[lhs.lowercased()] ?? 3
        let right = priority[rhs.lowercased()] ?? 3
        return left == right ? lhs < rhs : left < right
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chores = try container.decodeIfPresent(
            [String: SkylightCollectionResponse<SkylightChoreAttributes>].self,
            forKey: .chores
        ) ?? [:]
        routines = try container.decodeIfPresent(
            [String: SkylightCollectionResponse<SkylightChoreAttributes>].self,
            forKey: .routines
        ) ?? [:]
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

    enum CodingKeys: String, CodingKey {
        case name
        case pointValue = "point_value"
        case description
        case emojiIcon = "emoji_icon"
        case respawnOnRedemption = "respawn_on_redemption"
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

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
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
