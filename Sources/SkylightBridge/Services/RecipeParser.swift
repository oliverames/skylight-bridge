import Foundation

enum RecipeParser {
    private static let maximumInputBytes = 1_048_576
    private static let maximumLines = 5_000
    private static let maximumFieldCharacters = 4_096
    private static let maximumIngredients = 1_000
    private static let maximumInstructions = 1_000

    static func parse(_ note: String) throws -> RecipeDraft {
        guard note.utf8.count <= maximumInputBytes else {
            throw RecipeParserError.inputTooLarge
        }
        var lines = note.components(separatedBy: .newlines)
        guard lines.count <= maximumLines else {
            throw RecipeParserError.tooManyLines
        }
        guard lines.allSatisfy({ $0.count <= maximumFieldCharacters }) else {
            throw RecipeParserError.fieldTooLong
        }
        guard let titleIndex = lines.firstIndex(where: { !$0.trimmed.isEmpty }) else {
            throw RecipeParserError.emptyNote
        }

        let title = lines.remove(at: titleIndex).strippingMarkdownHeading.trimmed
        guard !title.isEmpty else {
            throw RecipeParserError.emptyNote
        }

        var builder = RecipeBuilder(title: title)
        var section = RecipeSection.summary

        for rawLine in lines {
            let line = rawLine.trimmed
            guard !line.isEmpty else { continue }

            if let heading = RecipeSection(heading: line) {
                section = heading
                continue
            }

            switch section {
            case .summary:
                builder.consumeSummary(line)
            case .ingredients:
                guard builder.ingredients.count < maximumIngredients else {
                    throw RecipeParserError.tooManyIngredients
                }
                builder.ingredients.append(line.strippingListMarker)
            case .instructions:
                guard builder.instructions.count < maximumInstructions else {
                    throw RecipeParserError.tooManyInstructions
                }
                builder.instructions.append(line.strippingListMarker)
            }
        }

        guard !builder.ingredients.isEmpty else {
            throw RecipeParserError.missingIngredients
        }
        guard !builder.instructions.isEmpty else {
            throw RecipeParserError.missingInstructions
        }

        return builder.recipe
    }
}

private enum RecipeSection {
    case summary
    case ingredients
    case instructions

    init?(heading: String) {
        switch heading.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":")) {
        case "ingredients": self = .ingredients
        case "instructions", "directions", "method": self = .instructions
        default: return nil
        }
    }
}

private struct RecipeBuilder {
    let title: String
    var descriptionLines: [String] = []
    var servings: String?
    var preparationTime: String?
    var cookingTime: String?
    var ingredients: [String] = []
    var instructions: [String] = []
    var tags: [String] = []
    var sourceURL: String?

    mutating func consumeSummary(_ line: String) {
        guard let field = line.keyValuePair else {
            descriptionLines.append(line)
            return
        }

        switch field.key.lowercased() {
        case "serves", "servings", "yield":
            servings = field.value
        case "prep", "preparation", "preparation time", "prep time":
            preparationTime = field.value
        case "cook", "cooking", "cooking time", "cook time":
            cookingTime = field.value
        case "tags", "categories":
            tags = field.value
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
        case "source", "source url", "url":
            sourceURL = field.value
        default:
            descriptionLines.append(line)
        }
    }

    var recipe: RecipeDraft {
        RecipeDraft(
            title: title,
            description: descriptionLines.isEmpty ? nil : descriptionLines.joined(separator: "\n"),
            servings: servings,
            preparationTime: preparationTime,
            cookingTime: cookingTime,
            ingredients: ingredients,
            instructions: instructions,
            tags: tags,
            sourceURL: sourceURL
        )
    }
}
