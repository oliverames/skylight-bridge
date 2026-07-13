enum SkylightEndpointEvidence: String, Equatable, Sendable {
    case liveTested
    case liveBundle
    case currentCommunity
    case experimental
    case stale

    var label: String {
        switch self {
        case .liveTested: "Live-tested"
        case .liveBundle: "Live bundle"
        case .currentCommunity: "Current client"
        case .experimental: "Experimental"
        case .stale: "Stale"
        }
    }
}

struct SkylightEndpoint: Identifiable, Equatable, Sendable {
    let method: String
    let path: String
    let evidence: SkylightEndpointEvidence
    let note: String?

    var id: String { "\(method) \(path)" }

    init(
        _ method: String,
        _ path: String,
        evidence: SkylightEndpointEvidence,
        note: String? = nil
    ) {
        self.method = method
        self.path = path
        self.evidence = evidence
        self.note = note
    }
}

struct SkylightEndpointGroup: Identifiable, Equatable, Sendable {
    let name: String
    let endpoints: [SkylightEndpoint]

    var id: String { name }
}

enum SkylightEndpointCatalog {
    static let groups: [SkylightEndpointGroup] = [
        authentication,
        frames,
        profiles,
        lists,
        photos,
        albums,
        chores,
        taskBox,
        rewards,
        meals,
        calendar,
        sidekick,
        notifications,
        assistant,
        plusAndAccount,
        staleAndExperimental
    ]

    private static let authentication = SkylightEndpointGroup(
        name: "Authentication",
        endpoints: [
            e("GET", "/auth/session/new", .liveBundle),
            e("POST", "/auth/session", .liveBundle),
            e("GET", "/oauth/authorize", .liveBundle),
            e("POST", "/oauth/token", .liveTested),
            e("POST", "/oauth/revoke", .liveBundle),
            e("POST", "/oauth/legacy_token_exchange", .liveBundle)
        ]
    )

    private static let frames = SkylightEndpointGroup(
        name: "Frames and devices",
        endpoints: [
            e("GET", "/frames", .liveTested),
            e("POST", "/frames", .liveBundle),
            e("GET", "/frames/{frameId}", .liveTested),
            e("PUT", "/frames/{frameId}", .liveBundle),
            e("POST", "/frames/{frameId}/activation_code", .liveBundle),
            e("POST", "/frames/{frameId}/hide", .liveBundle),
            e("GET", "/frames/{frameId}/month_in_review", .liveBundle),
            e("POST", "/frames/{frameId}/onboarding/complete", .liveBundle),
            e("PUT", "/frames/{frameId}/profile", .liveBundle),
            e("PUT", "/frames/{frameId}/purchase_metadata", .liveBundle),
            e("PUT", "/frames/{frameId}/rename", .liveBundle),
            e("POST", "/frames/{frameId}/share_token_redemptions", .liveBundle),
            e("POST", "/frames/{frameId}/transfer_to_new_user", .liveBundle),
            e("GET", "/frames/{frameId}/household_config", .liveBundle),
            e("PATCH", "/frames/{frameId}/household_config", .liveBundle),
            e("GET", "/frames/{frameId}/devices", .liveTested),
            e("POST", "/frames/{frameId}/devices", .liveBundle),
            e("GET", "/frames/{frameId}/devices/{deviceId}", .liveBundle),
            e("PUT", "/frames/{frameId}/devices/{deviceId}", .liveBundle, note: "Also sets current_album_id"),
            e("DELETE", "/frames/{frameId}/devices/{deviceId}", .liveBundle),
            e("POST", "/frames/{frameId}/devices/{deviceId}/activation_code", .liveBundle),
            e("POST", "/frames/{frameId}/devices/{deviceId}/authorize", .liveBundle),
            e("POST", "/frames/{frameId}/devices/{deviceId}/reset", .liveBundle),
            e("POST", "/frames/{frameId}/devices/{deviceId}/{action}", .liveBundle, note: "Dynamic device action"),
            e("GET", "/frames/{frameId}/devices/{deviceId}/alarms", .liveBundle),
            e("POST", "/frames/{frameId}/devices/{deviceId}/alarms", .liveBundle),
            e("PATCH", "/frames/{frameId}/devices/{deviceId}/alarms/{alarmId}", .liveBundle),
            e("DELETE", "/frames/{frameId}/devices/{deviceId}/alarms/{alarmId}", .liveBundle),
            e("GET", "/avatars", .liveTested),
            e("GET", "/colors", .liveTested)
        ]
    )

    private static let profiles = SkylightEndpointGroup(
        name: "Users and profiles",
        endpoints: [
            e("GET", "/frames/{frameId}/users", .liveBundle),
            e("POST", "/frames/{frameId}/users", .liveBundle),
            e("DELETE", "/frames/{frameId}/users/{userId}", .liveBundle, note: "Block or remove access"),
            e("POST", "/frames/{frameId}/users/{userId}/approve", .liveBundle, note: "Approve or restore access"),
            e("GET", "/frames/{frameId}/categories", .liveTested),
            e("POST", "/frames/{frameId}/categories", .liveTested),
            e("GET", "/frames/{frameId}/categories/{categoryId}", .liveBundle),
            e("PUT", "/frames/{frameId}/categories/{categoryId}", .liveTested),
            e("GET", "/frames/{frameId}/categories/{categoryId}/buddy_character", .liveBundle),
            e("PUT", "/frames/{frameId}/categories/{categoryId}/buddy_character", .liveBundle),
            e("PUT", "/frames/{frameId}/categories/{categoryId}/family_member", .liveBundle),
            e("PUT", "/frames/{frameId}/categories/{categoryId}/source_calendar_categorizations", .liveBundle),
            e("DELETE", "/frames/{frameId}/categories/{categoryId}", .liveTested)
        ]
    )

    private static let lists = SkylightEndpointGroup(
        name: "Lists",
        endpoints: [
            e("GET", "/frames/{frameId}/lists", .liveTested),
            e("POST", "/frames/{frameId}/lists", .liveTested),
            e("GET", "/frames/{frameId}/lists/{listId}", .liveTested),
            e("PUT", "/frames/{frameId}/lists/{listId}", .liveTested),
            e("DELETE", "/frames/{frameId}/lists/{listId}", .liveTested),
            e("GET", "/frames/{frameId}/lists/{listId}/list_items", .liveBundle),
            e("POST", "/frames/{frameId}/lists/{listId}/list_items", .liveTested),
            e("PUT", "/frames/{frameId}/lists/{listId}/list_items/{itemId}", .liveTested),
            e("DELETE", "/frames/{frameId}/lists/{listId}/list_items/{itemId}", .liveTested),
            e("POST", "/frames/{frameId}/lists/{listId}/list_items/{itemId}/move", .liveBundle),
            e("PUT", "/frames/{frameId}/lists/{listId}/list_items/bulk_update_section", .liveBundle),
            e("DELETE", "/frames/{frameId}/lists/{listId}/list_items/bulk_destroy", .liveBundle),
            e("POST", "/frames/{frameId}/lists/{listId}/organize", .currentCommunity),
            e("POST", "/frames/{frameId}/lists/{listId}/order", .currentCommunity)
        ]
    )

    private static let photos = SkylightEndpointGroup(
        name: "Photos and messages",
        endpoints: [
            e("GET", "/frames/{frameId}/messages", .liveBundle),
            e("GET", "/frames/{frameId}/messages/{messageId}", .liveBundle),
            e("DELETE", "/frames/{frameId}/messages/{messageId}", .liveBundle),
            e("DELETE", "/frames/{frameId}/messages/destroy_multiple", .liveBundle),
            e("PUT", "/frames/{frameId}/messages/{messageId}/caption", .liveBundle),
            e("GET", "/frames/{frameId}/messages/{messageId}/all_likes", .liveBundle),
            e("POST", "/frames/{frameId}/messages/{messageId}/likes", .liveBundle),
            e("DELETE", "/frames/{frameId}/messages/{messageId}/likes", .liveBundle),
            e("GET", "/frames/{frameId}/messages/{messageId}/comments", .liveBundle),
            e("POST", "/frames/{frameId}/messages/{messageId}/comments", .liveBundle),
            e("DELETE", "/frames/{frameId}/messages/{messageId}/comments/{commentId}", .liveBundle),
            e("POST", "/frames/{frameId}/copy_to_frames", .liveBundle),
            e("POST", "/upload_url", .currentCommunity),
            e("POST", "/message_upload_urls", .liveBundle, note: "Bulk element schema remains provisional"),
            e("POST", "/messages/uploads", .liveBundle),
            e("GET", "/messages/cloud_upload_credentials", .liveBundle)
        ]
    )

    private static let albums = SkylightEndpointGroup(
        name: "Albums",
        endpoints: [
            e("GET", "/frames/{frameId}/albums", .liveBundle),
            e("POST", "/frames/{frameId}/albums", .liveBundle),
            e("PATCH", "/frames/{frameId}/albums/{albumId}", .liveBundle),
            e("DELETE", "/frames/{frameId}/albums/{albumId}", .liveBundle),
            e("GET", "/frames/{frameId}/albums/{albumId}/messages", .liveBundle),
            e("GET", "/frames/{frameId}/albums/{albumId}/messages/all_ids", .liveBundle),
            e("POST", "/frames/{frameId}/albums/add_to", .liveBundle),
            e("POST", "/frames/{frameId}/albums/remove_from", .liveBundle)
        ]
    )

    private static let chores = SkylightEndpointGroup(
        name: "Chores and routines",
        endpoints: [
            e("GET", "/frames/{frameId}/chores", .liveTested),
            e("GET", "/frames/{frameId}/chores/all", .liveBundle),
            e("GET", "/frames/{frameId}/chores/search", .liveBundle),
            e("POST", "/frames/{frameId}/chores", .liveTested),
            e("POST", "/frames/{frameId}/chores/create_multiple", .liveTested),
            e("PUT", "/frames/{frameId}/chores/{choreId}", .liveTested),
            e("DELETE", "/frames/{frameId}/chores/{choreId}", .liveTested),
            e("PUT", "/frames/{frameId}/chores/{seriesId}/completions", .liveTested),
            e("POST", "/frames/{frameId}/chores/{choreId}/move", .liveBundle)
        ]
    )

    private static let taskBox = SkylightEndpointGroup(
        name: "Task Box",
        endpoints: [
            e("GET", "/frames/{frameId}/task_box/items", .liveBundle),
            e("POST", "/frames/{frameId}/task_box/items", .liveBundle),
            e("PATCH", "/frames/{frameId}/task_box/items/{itemId}", .liveBundle),
            e("DELETE", "/frames/{frameId}/task_box/items/{itemId}", .liveBundle)
        ]
    )

    private static let rewards = SkylightEndpointGroup(
        name: "Rewards",
        endpoints: [
            e("GET", "/frames/{frameId}/rewards", .liveTested),
            e("GET", "/frames/{frameId}/rewards/{rewardId}", .liveBundle),
            e("POST", "/frames/{frameId}/rewards", .liveTested),
            e("PATCH", "/frames/{frameId}/rewards/{rewardId}", .liveTested),
            e("DELETE", "/frames/{frameId}/rewards/{rewardId}", .liveTested),
            e("POST", "/frames/{frameId}/rewards/{rewardId}/redeem", .liveTested),
            e("POST", "/frames/{frameId}/rewards/{rewardId}/unredeem", .liveTested),
            e("GET", "/frames/{frameId}/reward_points", .liveTested),
            e("POST", "/frames/{frameId}/reward_points", .liveTested)
        ]
    )

    private static let meals = SkylightEndpointGroup(
        name: "Recipes and meals",
        endpoints: [
            e("GET", "/frames/{frameId}/meals/categories", .liveTested),
            e("PATCH", "/frames/{frameId}/meals/categories/{categoryId}", .liveBundle),
            e("GET", "/frames/{frameId}/meals/recipes", .liveTested),
            e("GET", "/frames/{frameId}/meals/recipes/{recipeId}", .liveTested),
            e("POST", "/frames/{frameId}/meals/recipes", .liveTested),
            e("PATCH", "/frames/{frameId}/meals/recipes/{recipeId}", .liveTested),
            e("DELETE", "/frames/{frameId}/meals/recipes/{recipeId}", .liveTested),
            e("POST", "/frames/{frameId}/meals/recipes/{recipeId}/add_to_grocery_list", .liveTested),
            e("GET", "/frames/{frameId}/meals/sittings", .liveTested),
            e("POST", "/frames/{frameId}/meals/sittings", .liveTested),
            e("GET", "/frames/{frameId}/meals/sittings/{mealId}/instances", .liveBundle),
            e("PATCH", "/frames/{frameId}/meals/sittings/{mealId}/instances/{instanceISO}", .liveBundle),
            e("DELETE", "/frames/{frameId}/meals/sittings/{mealId}/instances/{instanceISO}", .liveBundle),
            e("POST", "/frames/{frameId}/meals/sittings/migrate", .liveBundle)
        ]
    )

    private static let calendar = SkylightEndpointGroup(
        name: "Calendar client coverage",
        endpoints: [
            e("GET", "/frames/{frameId}/calendar_events", .liveTested),
            e("POST", "/frames/{frameId}/calendar_events", .liveTested),
            e("PUT", "/frames/{frameId}/calendar_events/{eventId}", .liveTested),
            e("DELETE", "/frames/{frameId}/calendar_events/{eventId}", .liveTested),
            e("GET", "/frames/{frameId}/calendar_events/search", .liveBundle),
            e("GET", "/frames/{frameId}/calendar_events/countdowns", .liveBundle),
            e("GET", "/frames/{frameId}/calendar_events/recent_invited_emails", .liveBundle),
            e("GET", "/frames/{frameId}/calendars", .liveBundle),
            e("GET", "/frames/{frameId}/calendars/{calendarId}", .liveBundle),
            e("GET", "/frames/{frameId}/calendars/authorization_request_url", .liveBundle),
            e("POST", "/frames/{frameId}/calendars/apple", .liveBundle),
            e("PUT", "/frames/{frameId}/calendars/{calendarId}", .liveBundle),
            e("GET", "/frames/{frameId}/source_calendars", .liveTested),
            e("GET", "/frames/{frameId}/source_calendars/{sourceId}", .liveBundle),
            e("POST", "/frames/{frameId}/source_calendars", .liveBundle),
            e("POST", "/frames/{frameId}/source_calendars/set_default_for_new_events", .liveBundle),
            e("PUT", "/frames/{frameId}/source_calendars/{sourceId}", .liveBundle),
            e("PUT", "/frames/{frameId}/source_calendars/{sourceId}/source_calendar_categorizations", .liveBundle),
            e("DELETE", "/frames/{frameId}/source_calendars/{sourceId}", .liveBundle),
            e("GET", "/frames/{frameId}/webcal_accounts", .liveBundle),
            e("POST", "/frames/{frameId}/webcal_accounts", .liveBundle)
        ]
    )

    private static let sidekick = SkylightEndpointGroup(
        name: "Sidekick and imports",
        endpoints: [
            e("GET", "/frames/{frameId}/auto_creation_intents", .liveBundle),
            e("POST", "/frames/{frameId}/auto_creation_intents", .liveBundle),
            e("GET", "/frames/{frameId}/auto_creation_intents/{intentId}", .liveBundle),
            e("POST", "/frames/{frameId}/auto_creation_intents/{intentId}/retry_draft", .liveBundle),
            e("POST", "/frames/{frameId}/auto_creation_intents/{intentId}/approve_draft", .liveBundle),
            e("POST", "/frames/{frameId}/auto_creation_intents/{intentId}/undo", .liveBundle),
            e("GET", "/frames/{frameId}/auto_creation_intents/{intentId}/created_items", .liveBundle),
            e("GET", "/frames/{frameId}/auto_creation_intents/{intentId}/created_events", .liveBundle),
            e("GET", "/frames/{frameId}/auto_creation_intents/{intentId}/created_events/{eventId}", .liveBundle),
            e("POST", "/frames/{frameId}/auto_creation_intents/{intentId}/created_events/bulk_approve", .liveBundle),
            e("GET", "/frames/{frameId}/auto_creation_intents/{intentId}/created_recipes", .liveBundle),
            e("GET", "/frames/{frameId}/auto_creation_intents/{intentId}/created_recipes/{recipeId}", .liveBundle),
            e("POST", "/frames/{frameId}/auto_creation_intents/{intentId}/created_recipes/bulk_approve", .liveBundle)
        ]
    )

    private static let notifications = SkylightEndpointGroup(
        name: "Notifications and nudges",
        endpoints: [
            e("GET", "/frames/{frameId}/event_notification_settings", .liveBundle),
            e("PUT", "/frames/{frameId}/event_notification_settings", .liveBundle),
            e("GET", "/frames/{frameId}/task_notification_settings", .liveBundle),
            e("PATCH", "/frames/{frameId}/task_notification_settings", .liveBundle),
            e("GET", "/reminder_profile", .liveBundle),
            e("PUT", "/reminder_profile", .liveBundle),
            e("GET", "/frames/{frameId}/nudges", .liveBundle),
            e("POST", "/frames/{frameId}/nudges", .liveBundle),
            e("PATCH", "/frames/{frameId}/nudges/{nudgeId}", .liveBundle),
            e("DELETE", "/frames/{frameId}/nudges/{nudgeId}", .liveBundle)
        ]
    )

    private static let assistant = SkylightEndpointGroup(
        name: "Assistant households",
        endpoints: [
            e("POST", "/frames/ask", .liveBundle),
            e("POST", "/frames/{frameId}/assistant_household", .liveBundle),
            e("GET", "/assistant_households/{householdId}", .liveBundle),
            e("POST", "/assistant_households/{householdId}/ping", .liveBundle),
            e("POST", "/assistant_trial", .liveBundle)
        ]
    )

    private static let plusAndAccount = SkylightEndpointGroup(
        name: "Plus and account",
        endpoints: [
            e("GET", "/plus_access", .liveBundle),
            e("POST", "/plus_access/resend_entitlement_email", .liveBundle),
            e("POST", "/plus_permissions", .liveBundle),
            e("POST", "/plus_permissions/start_trial", .liveBundle),
            e("POST", "/plus_permissions/share_plus", .liveBundle),
            e("POST", "/plus_purchases", .liveBundle),
            e("POST", "/plus_receipts", .liveBundle),
            e("GET", "/user", .liveBundle),
            e("PUT", "/user", .liveBundle),
            e("DELETE", "/user", .liveBundle),
            e("PATCH", "/user/profile", .liveBundle),
            e("PATCH", "/user/klaviyo_toggler", .liveBundle),
            e("PATCH", "/user/push_toggler", .liveBundle),
            e("POST", "/user/export", .liveBundle),
            e("POST", "/user/referral_code", .liveBundle),
            e("POST", "/password_resets", .liveBundle),
            e("GET", "/activities", .liveBundle),
            e("GET", "/month_in_reviews", .liveBundle)
        ]
    )

    private static let staleAndExperimental = SkylightEndpointGroup(
        name: "Stale and experimental",
        endpoints: [
            e("POST", "/sessions", .stale, note: "Legacy API session login"),
            e("PATCH", "/frames/{frameId}", .stale, note: "Older clients updated frames with PATCH; the live bundle uses PUT"),
            e("POST", "/frames/{frameId}/users/{userId}/block", .stale),
            e("DELETE", "/frames/{frameId}/users/{userId}/block", .stale),
            e("GET", "/frames/{frameId}/task_box_items", .stale),
            e("POST", "/frames/{frameId}/task_box_items", .stale),
            e("GET", "/frames/{frameId}/routines", .experimental),
            e("POST", "/frames/{frameId}/routines", .experimental),
            e("PUT", "/frames/{frameId}/routines/{routineId}", .experimental),
            e("DELETE", "/frames/{frameId}/routines/{routineId}", .experimental),
            e("PATCH", "/frames/{frameId}/routines/reorder", .experimental)
        ]
    )

    private static func e(
        _ method: String,
        _ path: String,
        _ evidence: SkylightEndpointEvidence,
        note: String? = nil
    ) -> SkylightEndpoint {
        SkylightEndpoint(method, path, evidence: evidence, note: note)
    }
}
