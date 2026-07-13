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

    enum CodingKeys: String, CodingKey {
        case label
        case color
        case kind
        case hideOnDevice = "hide_on_device"
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
    let redirectURL: String

    enum CodingKeys: String, CodingKey {
        case redirectURL = "redirect_url"
    }
}
