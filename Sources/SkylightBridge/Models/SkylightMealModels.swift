struct SkylightMealCategoryAttributes: Codable, Equatable, Sendable {
    let label: String?
    let color: String?
}

struct SkylightMealCategoryRequest: Codable, Equatable, Sendable {
    let label: String?
    let color: String?

    init(label: String? = nil, color: String? = nil) {
        self.label = label
        self.color = color
    }
}

struct SkylightRecipeAttributes: Codable, Equatable, Sendable {
    let summary: String?
    let description: String?
    let ingredients: [String]?
    let url: String?
    let imageURL: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case ingredients
        case url
        case imageURL = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SkylightRecipeRequest: Codable, Equatable, Sendable {
    let mealCategoryID: String?
    let summary: String
    let description: String?
    let ingredients: [String]?
    let url: String?

    init(
        mealCategoryID: String? = nil,
        summary: String,
        description: String? = nil,
        ingredients: [String]? = nil,
        url: String? = nil
    ) {
        self.mealCategoryID = mealCategoryID
        self.summary = summary
        self.description = description
        self.ingredients = ingredients
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case mealCategoryID = "meal_category_id"
        case summary
        case description
        case ingredients
        case url
    }
}

struct SkylightMealSittingAttributes: Codable, Equatable, Sendable {
    let summary: String?
    let description: String?
    let note: String?
    let date: String?
    let addToGroceryList: Bool?
    let rrule: [String]?

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case note
        case date
        case addToGroceryList = "add_to_grocery_list"
        case rrule
    }
}

struct SkylightMealSittingRequest: Codable, Equatable, Sendable {
    let date: String
    let summary: String?
    let description: String?
    let note: String?
    let mealRecipeID: String?
    let mealCategoryID: String?
    let addToGroceryList: Bool?
    let rrule: [String]?

    init(
        date: String,
        summary: String? = nil,
        description: String? = nil,
        note: String? = nil,
        mealRecipeID: String? = nil,
        mealCategoryID: String? = nil,
        addToGroceryList: Bool? = nil,
        rrule: [String]? = nil
    ) {
        self.date = date
        self.summary = summary
        self.description = description
        self.note = note
        self.mealRecipeID = mealRecipeID
        self.mealCategoryID = mealCategoryID
        self.addToGroceryList = addToGroceryList
        self.rrule = rrule
    }

    enum CodingKeys: String, CodingKey {
        case date
        case summary
        case description
        case note
        case mealRecipeID = "meal_recipe_id"
        case mealCategoryID = "meal_category_id"
        case addToGroceryList = "add_to_grocery_list"
        case rrule
    }
}

struct SkylightMealInstanceUpdateRequest: Codable, Equatable, Sendable {
    let summary: String?
    let description: String?
    let note: String?
    let mealRecipeID: String?
    let mealCategoryID: String?
    let addToGroceryList: Bool?

    init(
        summary: String? = nil,
        description: String? = nil,
        note: String? = nil,
        mealRecipeID: String? = nil,
        mealCategoryID: String? = nil,
        addToGroceryList: Bool? = nil
    ) {
        self.summary = summary
        self.description = description
        self.note = note
        self.mealRecipeID = mealRecipeID
        self.mealCategoryID = mealCategoryID
        self.addToGroceryList = addToGroceryList
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case note
        case mealRecipeID = "meal_recipe_id"
        case mealCategoryID = "meal_category_id"
        case addToGroceryList = "add_to_grocery_list"
    }
}
