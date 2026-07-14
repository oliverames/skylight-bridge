import Testing
@testable import SkylightBridge

struct RecipeParserTests {
    @Test("A structured Apple Note becomes a recipe draft")
    func parsesStructuredRecipe() throws {
        let note = """
        Chicken Parmesan

        Serves: 4
        Prep: 20 minutes
        Cook: 35 minutes

        Ingredients
        - 2 chicken breasts
        - 1 cup breadcrumbs
        - Tomato sauce

        Instructions
        1. Prepare the chicken.
        2. Bake until cooked.
        """

        let recipe = try RecipeParser.parse(note)

        #expect(recipe.title == "Chicken Parmesan")
        #expect(recipe.servings == "4")
        #expect(recipe.preparationTime == "20 minutes")
        #expect(recipe.cookingTime == "35 minutes")
        #expect(recipe.ingredients == ["2 chicken breasts", "1 cup breadcrumbs", "Tomato sauce"])
        #expect(recipe.instructions == ["Prepare the chicken.", "Bake until cooked."])
    }

    @Test("A title and description alone form a valid recipe draft")
    func parsesDescriptionOnlyNote() throws {
        let recipe = try RecipeParser.parse("Grandma's Soup\nA cozy classic.")

        #expect(recipe.title == "Grandma's Soup")
        #expect(recipe.description == "A cozy classic.")
        #expect(recipe.ingredients.isEmpty)
        #expect(recipe.instructions.isEmpty)
    }
}
