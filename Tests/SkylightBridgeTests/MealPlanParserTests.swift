import Testing
@testable import SkylightBridge

struct MealPlanParserTests {
    @Test("Weekly meal-plan lines produce categorized entries")
    func parsesWeeklyMealPlan() throws {
        let note = """
        Monday Dinner: Chicken Parmesan
        Tuesday Dinner: Tacos
        Wednesday Lunch: Leftovers
        """

        let meals = try MealPlanParser.parse(note)

        #expect(meals == [
            PlannedMeal(day: "Monday", category: "Dinner", recipeTitle: "Chicken Parmesan"),
            PlannedMeal(day: "Tuesday", category: "Dinner", recipeTitle: "Tacos"),
            PlannedMeal(day: "Wednesday", category: "Lunch", recipeTitle: "Leftovers")
        ])
    }

    @Test("An over-long comment line is rejected like any other line")
    func rejectsOverlongCommentLine() {
        let longComment = "#" + String(repeating: "x", count: 600)

        #expect(throws: MealPlanParserError.fieldTooLong) {
            try MealPlanParser.parse(longComment)
        }
    }
}
