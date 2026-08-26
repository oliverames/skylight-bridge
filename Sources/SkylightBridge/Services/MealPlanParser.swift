import Foundation

enum MealPlanParserError: Error, LocalizedError, Equatable, Sendable {
    case inputTooLarge
    case tooManyMeals
    case fieldTooLong
    case invalidLine(Int)

    var errorDescription: String? {
        switch self {
        case .inputTooLarge:
            "The meal plan is too large to synchronize safely."
        case .tooManyMeals:
            "The meal plan contains too many entries to synchronize safely."
        case .fieldTooLong:
            "A meal-plan entry is too long to synchronize safely."
        case let .invalidLine(line):
            "Meal-plan line \(line) is not in the expected ‘Day Meal: Recipe’ format."
        }
    }
}

enum MealPlanParser {
    private static let maximumInputBytes = 1_048_576
    private static let maximumMeals = 512
    private static let maximumLineCharacters = 512

    static func parse(_ note: String) throws -> [PlannedMeal] {
        guard note.utf8.count <= maximumInputBytes else {
            throw MealPlanParserError.inputTooLarge
        }

        var meals: [PlannedMeal] = []
        for (index, rawLine) in note.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmed
            guard !line.isEmpty else { continue }
            guard line.count <= maximumLineCharacters else {
                throw MealPlanParserError.fieldTooLong
            }
            if line.hasPrefix("#") || ["meal plan", "weekly meal plan"].contains(line.lowercased()) {
                continue
            }
            guard let meal = parseLine(line) else {
                throw MealPlanParserError.invalidLine(index + 1)
            }
            guard meals.count < maximumMeals else {
                throw MealPlanParserError.tooManyMeals
            }
            meals.append(meal)
        }
        return meals
    }

    private static func parseLine(_ rawLine: String) -> PlannedMeal? {
        let line = rawLine.trimmed.strippingListMarker
        guard let separator = line.firstIndex(of: ":") else { return nil }

        let schedule = String(line[..<separator]).trimmed
        let recipeTitle = String(line[line.index(after: separator)...]).trimmed
        let scheduleParts = schedule.split(whereSeparator: \.isWhitespace)

        guard scheduleParts.count >= 2, !recipeTitle.isEmpty else { return nil }

        let category = String(scheduleParts.last!)
        let day = scheduleParts.dropLast().joined(separator: " ")
        guard !day.isEmpty, !category.isEmpty else { return nil }

        return PlannedMeal(day: day, category: category, recipeTitle: recipeTitle)
    }
}
