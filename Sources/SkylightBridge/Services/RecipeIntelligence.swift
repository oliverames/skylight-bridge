import Foundation
import FoundationModels

/// A meal-category label and title emoji for one recipe.
struct RecipeClassification: Equatable, Sendable {
    /// One of the category labels the caller offered (e.g. "Dinner").
    let categoryLabel: String
    /// A single emoji that represents the dish (e.g. "🥯").
    let emoji: String
}

/// Classifies recipes into meal categories and picks a title emoji. The live
/// implementation runs Apple's on-device model, so recipe titles never leave
/// the Mac; tests inject a deterministic stub.
protocol RecipeClassifying: Sendable {
    /// False when Apple Intelligence is off or the model is not ready; callers
    /// fall back to the pre-classification behavior (first category, no emoji).
    var isAvailable: Bool { get async }

    /// Returns nil when the model is unavailable or generation fails; a recipe
    /// is never blocked from syncing by a classification failure.
    func classify(
        title: String,
        ingredients: [String],
        categoryLabels: [String]
    ) async -> RecipeClassification?
}

@Generable(description: "A meal category and one representative emoji for a recipe")
private struct GeneratedRecipeClassification {
    @Guide(description: "The meal category, exactly one of the offered options")
    var category: String

    @Guide(description: "A single emoji character that best represents the dish")
    var emoji: String
}

/// FoundationModels-backed classifier. An actor so requests serialize: a
/// LanguageModelSession handles one request at a time.
actor RecipeIntelligence: RecipeClassifying {
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// One short sentence for Activity when classification is skipped.
    static var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "this Mac does not support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence is turned off in System Settings"
        case .unavailable(.modelNotReady):
            "the on-device model is still downloading"
        case .unavailable:
            "the on-device model is unavailable"
        }
    }

    func classify(
        title: String,
        ingredients: [String],
        categoryLabels: [String]
    ) async -> RecipeClassification? {
        guard isAvailable, !categoryLabels.isEmpty else { return nil }

        let instructions = """
            You classify recipes for a family meal planner.
            Pick the single meal category that best fits the dish, choosing \
            exactly one of the offered category names, spelled exactly as offered.
            Also pick one emoji that best represents the dish.
            """
        let ingredientList = ingredients.prefix(12).joined(separator: ", ")
        let prompt = """
            Recipe: \(title.prefix(120))
            \(ingredientList.isEmpty ? "" : "Ingredients: \(ingredientList.prefix(300))")
            Offered categories: \(categoryLabels.joined(separator: ", "))
            """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: String(prompt),
                generating: GeneratedRecipeClassification.self
            )
            let category = response.content.category.trimmed
            let emoji = firstEmoji(in: response.content.emoji)
            // The model is asked to echo an offered label; anything else means
            // the classification cannot be trusted, so match case-insensitively
            // and fail closed.
            guard let matched = categoryLabels.first(where: {
                $0.compare(category, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else { return nil }
            guard let emoji else { return nil }
            return RecipeClassification(categoryLabel: matched, emoji: emoji)
        } catch {
            return nil
        }
    }

    /// Extracts the first emoji grapheme from model output, which can include
    /// stray words or multiple emoji despite the guide.
    private func firstEmoji(in value: String) -> String? {
        for character in value where character.isRecipeEmoji {
            return String(character)
        }
        return nil
    }
}

extension Character {
    /// True for pictographic emoji; deliberately false for digits and other
    /// characters that report `isEmoji` without emoji presentation.
    var isRecipeEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value >= 0x1F000)
        }
    }
}

extension String {
    /// True when the title already starts with an emoji (ignoring whitespace).
    var hasLeadingEmoji: Bool {
        guard let first = trimmed.first else { return false }
        return first.isRecipeEmoji
    }
}
