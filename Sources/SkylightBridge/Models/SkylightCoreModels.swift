struct SkylightFeatureState: Codable, Equatable, Sendable {
    let enabled: Bool
}

enum SkylightJSONValue: Codable, Equatable, Sendable {
    case object([String: SkylightJSONValue])
    case array([SkylightJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([SkylightJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: SkylightJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct SkylightFrameAttributes: Codable, Equatable, Sendable {
    let name: String?
    let timezone: String?
    let plus: Bool?
    let featureBundle: SkylightJSONValue?

    enum CodingKeys: String, CodingKey {
        case name
        case timezone
        case plus
        case featureBundle = "feature_bundle"
    }
}

struct SkylightFrameUpdateRequest: Codable, Equatable, Sendable {
    let householdName: String?
    let timezone: String?
    let openToPublic: Bool?
    let messageViewability: String?

    init(
        householdName: String? = nil,
        timezone: String? = nil,
        openToPublic: Bool? = nil,
        messageViewability: String? = nil
    ) {
        self.householdName = householdName
        self.timezone = timezone
        self.openToPublic = openToPublic
        self.messageViewability = messageViewability
    }

    enum CodingKeys: String, CodingKey {
        case householdName = "household_name"
        case timezone
        case openToPublic = "open_to_public"
        case messageViewability = "message_viewability"
    }
}

struct SkylightDeviceAttributes: Codable, Equatable, Sendable {
    let name: String?
    let activated: Bool?
    let timezone: String?
    let role: String?
    let categoryID: String?
    let brightness: Int?
    let sleepsAt: String?
    let wakesAt: String?
    let currentlySleeping: Bool?
    let sleepModeOn: Bool?
    let sleepMode: String?
    let nightlight: Bool?
    let nightlightBrightness: Int?
    let currentAlbumID: String?

    enum CodingKeys: String, CodingKey {
        case name
        case activated
        case timezone
        case role
        case categoryID = "category_id"
        case brightness
        case sleepsAt = "sleeps_at"
        case wakesAt = "wakes_at"
        case currentlySleeping = "currently_sleeping"
        case sleepModeOn = "sleep_mode_on"
        case sleepMode = "sleep_mode"
        case nightlight
        case nightlightBrightness = "nightlight_brightness"
        case currentAlbumID = "current_album_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        activated = try container.decodeIfPresent(Bool.self, forKey: .activated)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        categoryID = Self.flexibleString(in: container, forKey: .categoryID)
        brightness = try container.decodeIfPresent(Int.self, forKey: .brightness)
        sleepsAt = try container.decodeIfPresent(String.self, forKey: .sleepsAt)
        wakesAt = try container.decodeIfPresent(String.self, forKey: .wakesAt)
        currentlySleeping = try container.decodeIfPresent(Bool.self, forKey: .currentlySleeping)
        sleepModeOn = try container.decodeIfPresent(Bool.self, forKey: .sleepModeOn)
        sleepMode = try container.decodeIfPresent(String.self, forKey: .sleepMode)
        nightlight = try container.decodeIfPresent(Bool.self, forKey: .nightlight)
        nightlightBrightness = try container.decodeIfPresent(Int.self, forKey: .nightlightBrightness)
        currentAlbumID = Self.flexibleString(in: container, forKey: .currentAlbumID)
    }

    private static func flexibleString(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct SkylightDeviceUpdateRequest: Codable, Equatable, Sendable {
    let name: String?
    let brightness: Int?
    let timezone: String?
    let sleepModeOn: Bool?
    let currentAlbumID: String?

    init(
        name: String? = nil,
        brightness: Int? = nil,
        timezone: String? = nil,
        sleepModeOn: Bool? = nil,
        currentAlbumID: String? = nil
    ) {
        self.name = name
        self.brightness = brightness
        self.timezone = timezone
        self.sleepModeOn = sleepModeOn
        self.currentAlbumID = currentAlbumID
    }

    enum CodingKeys: String, CodingKey {
        case name
        case brightness
        case timezone
        case sleepModeOn = "sleep_mode_on"
        case currentAlbumID = "current_album_id"
    }
}

struct SkylightDeviceAlbumSelectionRequest: Codable, Equatable, Sendable {
    let currentAlbumID: String

    enum CodingKeys: String, CodingKey {
        case currentAlbumID = "current_album_id"
    }
}

struct SkylightUserAttributes: Codable, Equatable, Sendable {
    let email: String?
    let name: String?
    let role: String?
    let blocked: Bool?
}

struct SkylightUserAccessRequest: Codable, Equatable, Sendable {
    let email: String
}

struct SkylightCategoryAttributes: Codable, Equatable, Sendable {
    let label: String?
    let color: String?
    let profilePicURL: String?
    let linkedToProfile: Bool?
    let selectedForChoreChart: Bool?

    enum CodingKeys: String, CodingKey {
        case label
        case color
        case profilePicURL = "profile_pic_url"
        case linkedToProfile = "linked_to_profile"
        case selectedForChoreChart = "selected_for_chore_chart"
    }
}

struct SkylightCategoryRequest: Codable, Equatable, Sendable {
    let label: String?
    let color: String?
    let linkedToProfile: Bool?
    let selectedForChoreChart: Bool?

    init(
        label: String? = nil,
        color: String? = nil,
        linkedToProfile: Bool? = nil,
        selectedForChoreChart: Bool? = nil
    ) {
        self.label = label
        self.color = color
        self.linkedToProfile = linkedToProfile
        self.selectedForChoreChart = selectedForChoreChart
    }

    enum CodingKeys: String, CodingKey {
        case label
        case color
        case linkedToProfile = "linked_to_profile"
        case selectedForChoreChart = "selected_for_chore_chart"
    }
}

struct SkylightAvatarAttributes: Codable, Equatable, Sendable {
    let name: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case imageURL = "image_url"
    }
}

struct SkylightColor: Codable, Equatable, Sendable {
    let name: String?
    let hex: String?
}

struct SkylightColorsResponse: Codable, Equatable, Sendable {
    let data: [SkylightColor]
}

struct SkylightPlusAccessAttributes: Codable, Equatable, Sendable {
    let enabled: Bool?
    let plus: Bool?
}

struct SkylightPlusAccessResponse: Codable, Equatable, Sendable {
    let data: SkylightPlusAccessAttributes
}
