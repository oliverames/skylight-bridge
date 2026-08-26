enum SkylightListKind: String, Codable, CaseIterable, Equatable, Sendable {
    case toDo = "to_do"
    case shopping
    case other
}

enum SkylightListItemStatus: String, Codable, Equatable, Sendable {
    case pending
    case completed
}

struct SkylightListAttributes: Codable, Equatable, Sendable {
    let label: String?
    let color: String?
    let kind: SkylightListKind?
    let hideOnDevice: Bool?

    init(
        label: String? = nil,
        color: String? = nil,
        kind: SkylightListKind? = nil,
        hideOnDevice: Bool? = nil
    ) {
        self.label = label
        self.color = color
        self.kind = kind
        self.hideOnDevice = hideOnDevice
    }

    enum CodingKeys: String, CodingKey {
        case label
        case color
        case kind
        case hideOnDevice = "hide_on_device"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        kind = try TolerantDecoding.enumValue(
            SkylightListKind.self, from: container, forKey: .kind
        )
        hideOnDevice = try container.decodeIfPresent(Bool.self, forKey: .hideOnDevice)
    }
}

struct SkylightListRequest: Codable, Equatable, Sendable {
    let label: String?
    let color: String?
    let kind: SkylightListKind?
    let hideOnDevice: Bool?

    init(
        label: String? = nil,
        color: String? = nil,
        kind: SkylightListKind? = nil,
        hideOnDevice: Bool? = nil
    ) {
        self.label = label
        self.color = color
        self.kind = kind
        self.hideOnDevice = hideOnDevice
    }

    enum CodingKeys: String, CodingKey {
        case label
        case color
        case kind
        case hideOnDevice = "hide_on_device"
    }
}

struct SkylightListItemAttributes: Codable, Equatable, Sendable {
    let label: String?
    let status: SkylightListItemStatus?
    let section: String?
    let position: Int?

    init(
        label: String? = nil,
        status: SkylightListItemStatus? = nil,
        section: String? = nil,
        position: Int? = nil
    ) {
        self.label = label
        self.status = status
        self.section = section
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case label
        case status
        case section
        case position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        status = try TolerantDecoding.enumValue(
            SkylightListItemStatus.self, from: container, forKey: .status
        )
        section = try container.decodeIfPresent(String.self, forKey: .section)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
    }
}

struct SkylightListItemRequest: Codable, Equatable, Sendable {
    let label: String?
    let status: SkylightListItemStatus?
    let section: String?
    let position: Int?

    init(
        label: String? = nil,
        status: SkylightListItemStatus? = nil,
        section: String? = nil,
        position: Int? = nil
    ) {
        self.label = label
        self.status = status
        self.section = section
        self.position = position
    }
}

struct SkylightListCollectionResponse: Codable, Equatable, Sendable {
    let data: [SkylightResource<SkylightListAttributes>]
    let included: [SkylightResource<SkylightListItemAttributes>]?
}

struct SkylightListDetailResponse: Codable, Equatable, Sendable {
    let data: SkylightResource<SkylightListAttributes>
    let included: [SkylightResource<SkylightListItemAttributes>]?
}

struct SkylightMoveListItemRequest: Codable, Equatable, Sendable {
    let afterItemID: String?

    enum CodingKeys: String, CodingKey {
        case afterItemID = "after_item_id"
    }
}

struct SkylightBulkListSectionRequest: Codable, Equatable, Sendable {
    let itemIDs: [String]
    let section: String

    enum CodingKeys: String, CodingKey {
        case itemIDs = "item_ids"
        case section
    }
}

struct SkylightBulkListDeleteRequest: Codable, Equatable, Sendable {
    let ids: [String]
}

struct SkylightGroceryOrderRequest: Codable, Equatable, Sendable {
    let retailer: String?
}

struct SkylightGroceryOrderResponse: Codable, Equatable, Sendable {
    // The redirect_url payload is surfaced by the endpoint wrapper in
    // Diagnostics but the bridge itself never follows it.
}
