import Testing
@testable import SkylightBridge

struct MealPlanParserTests {
    @Test("Weekly meal-plan lines produce categorized entries")
    func parsesWeeklyMealPlan() {
        let note = """
        Monday Dinner: Chicken Parmesan
        Tuesday Dinner: Tacos
        Wednesday Lunch: Leftovers
        """

        let meals = MealPlanParser.parse(note)

        #expect(meals == [
            PlannedMeal(day: "Monday", category: "Dinner", recipeTitle: "Chicken Parmesan"),
            PlannedMeal(day: "Tuesday", category: "Dinner", recipeTitle: "Tacos"),
            PlannedMeal(day: "Wednesday", category: "Lunch", recipeTitle: "Leftovers")
        ])
    }
}
