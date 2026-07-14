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
            // Strip object-replacement characters (U+FFFC) that Apple Notes
            // leaves where inline images and other attachments sit, so they
            // never become bogus ingredient or instruction lines.
            let line = rawLine.replacingOccurrences(of: "\u{FFFC}", with: "").trimmed
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

    private static let recognizedFieldKeys: Set<String> = [
        "serves", "servings", "yield",
        "prep", "preparation", "preparation time", "prep time",
        "cook", "cooking", "cooking time", "cook time",
        "tags", "categories",
        "source", "source url", "url"
    ]

    mutating func consumeSummary(_ line: String) {
        // A single note line can pack several labeled fields separated by
        // bullets, e.g. "Source: AllRecipes • Servings: 8". Split only when
        // every segment is a recognized field, so bulleted prose stays intact.
        if line.contains("•") {
            let segments = line
                .split(separator: "•")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
            if segments.count > 1, segments.allSatisfy(Self.isRecognizedField) {
                for segment in segments {
                    consumeField(segment)
                }
                return
            }
        }
        consumeField(line)
    }

    private static func isRecognizedField(_ segment: String) -> Bool {
        guard let field = segment.keyValuePair else { return false }
        return recognizedFieldKeys.contains(field.key.lowercased())
    }

    private mutating func consumeField(_ line: String) {
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
            // Skylight's url field expects a real link; keep a plain source name
            // (like "AllRecipes") in the description instead of the url field.
            if Self.looksLikeURL(field.value) {
                sourceURL = field.value
            } else {
                descriptionLines.append(line)
            }
        default:
            descriptionLines.append(line)
        }
    }

    private static func looksLikeURL(_ value: String) -> Bool {
        let value = value.trimmed
        if value.contains("://") || value.hasPrefix("www.") {
            return true
        }
        return !value.contains(" ") && value.contains(".")
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
