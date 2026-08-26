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

    @Test("Decimal quantities survive list-marker stripping")
    func preservesDecimalQuantities() throws {
        let note = """
        Cookies

        Ingredients
        0.5 cup sugar
        1.5 cups milk
        2) one whole egg

        Instructions
        1. Whisk the dry mix.
        """

        let recipe = try RecipeParser.parse(note)

        #expect(recipe.ingredients == ["0.5 cup sugar", "1.5 cups milk", "one whole egg"])
        #expect(recipe.instructions == ["Whisk the dry mix."])
    }

    @Test("A bullet-packed metadata line splits into separate fields")
    func splitsBulletPackedFields() throws {
        let note = """
        🥞 Classic Pancakes
        Source: AllRecipes • Servings: 8

        Ingredients
        1 ½ cups flour

        Directions
        Mix and cook.
        """

        let recipe = try RecipeParser.parse(note)

        #expect(recipe.servings == "8")
        // "AllRecipes" is not a URL, so it stays in the description rather than
        // polluting the Skylight url field.
        #expect(recipe.sourceURL == nil)
        #expect(recipe.description?.contains("Source: AllRecipes") == true)
        #expect(recipe.ingredients == ["1 ½ cups flour"])
        #expect(recipe.instructions == ["Mix and cook."])
    }

    @Test("Attachment placeholder characters are ignored")
    func ignoresAttachmentPlaceholders() throws {
        let note = "Potato Salad\n\nIngredients\n6 potatoes\n\nInstructions\nBoil them.\n\n\u{FFFC}\n\u{FFFC}"

        let recipe = try RecipeParser.parse(note)

        #expect(recipe.ingredients == ["6 potatoes"])
        #expect(recipe.instructions == ["Boil them."])
    }

    @Test("A real source URL is captured into the url field")
    func capturesRealSourceURL() throws {
        let note = "Soup\nSource: https://example.com/soup\n\nIngredients\nWater\n\nInstructions\nHeat."

        let recipe = try RecipeParser.parse(note)

        #expect(recipe.sourceURL == "https://example.com/soup")
        #expect(recipe.description == nil)
    }
}
