enum MealPlanParser {
    static func parse(_ note: String) -> [PlannedMeal] {
        note.components(separatedBy: .newlines).compactMap(parseLine)
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
