enum RecipeParserError: Error, Equatable, Sendable {
    case emptyNote
    case inputTooLarge
    case tooManyLines
    case fieldTooLong
    case tooManyIngredients
    case tooManyInstructions
    case missingIngredients
    case missingInstructions
}

struct RecipeDraft: Equatable, Sendable {
    let title: String
    let description: String?
    let servings: String?
    let preparationTime: String?
    let cookingTime: String?
    let ingredients: [String]
    let instructions: [String]
    let tags: [String]
    let sourceURL: String?

    init(
        title: String,
        description: String? = nil,
        servings: String? = nil,
        preparationTime: String? = nil,
        cookingTime: String? = nil,
        ingredients: [String] = [],
        instructions: [String] = [],
        tags: [String] = [],
        sourceURL: String? = nil
    ) {
        self.title = title
        self.description = description
        self.servings = servings
        self.preparationTime = preparationTime
        self.cookingTime = cookingTime
        self.ingredients = ingredients
        self.instructions = instructions
        self.tags = tags
        self.sourceURL = sourceURL
    }
}
