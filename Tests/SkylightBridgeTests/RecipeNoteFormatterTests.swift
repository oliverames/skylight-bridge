import Testing
@testable import SkylightBridge

struct RecipeNoteFormatterTests {
    @Test("A full recipe draft survives the note round trip")
    func roundTripsFullDraft() throws {
        let draft = RecipeDraft(
            title: "Chicken Parmesan",
            description: "Weeknight classic",
            servings: "4",
            preparationTime: "20 minutes",
            cookingTime: "35 minutes",
            ingredients: ["2 chicken breasts", "1 cup breadcrumbs"],
            instructions: ["Prepare the chicken.", "Bake until cooked."],
            tags: ["dinner", "italian"],
            sourceURL: "https://example.com/chicken"
        )

        let parsed = try RecipeParser.parse(RecipeNoteFormatter.plaintext(for: draft))

        #expect(parsed == draft)
    }

    @Test("A freeform Skylight recipe becomes a stable note")
    func decodesForeignRecipe() throws {
        let attributes = SkylightRecipeAttributes(
            summary: "Grandma's Soup",
            description: "A cozy classic from the Skylight app.",
            ingredients: ["Carrots", "Stock"],
            url: "https://example.com/soup",
            imageURL: nil,
            createdAt: nil,
            updatedAt: "2026-07-01T00:00:00Z"
        )

        let draft = RecipeNoteFormatter.draft(from: attributes)

        #expect(draft.title == "Grandma's Soup")
        #expect(draft.description == "A cozy classic from the Skylight app.")
        #expect(draft.ingredients == ["Carrots", "Stock"])
        #expect(draft.instructions.isEmpty)
        #expect(draft.sourceURL == "https://example.com/soup")

        // Writing the note and parsing it back must not drift, or every pull
        // would trigger a push on the next cycle.
        let parsed = try RecipeParser.parse(RecipeNoteFormatter.plaintext(for: draft))
        #expect(parsed == draft)
    }

    @Test("Bridge-composed Skylight descriptions decode into structured drafts")
    func decodesBridgeComposedRecipe() throws {
        let original = RecipeDraft(
            title: "Tacos",
            description: "Family favorite",
            servings: "6",
            ingredients: ["Shells", "Cheese"],
            instructions: ["Fill the shells."],
            tags: ["dinner"],
            sourceURL: "https://example.com/tacos"
        )
        let attributes = SkylightRecipeAttributes(
            summary: original.title,
            description: RecipeNoteFormatter.skylightDescription(for: original),
            ingredients: original.ingredients,
            url: original.sourceURL,
            imageURL: nil,
            createdAt: nil,
            updatedAt: "rev-1"
        )

        #expect(RecipeNoteFormatter.draft(from: attributes) == original)
    }

    @Test("Note bodies escape HTML and keep one line per div")
    func rendersBodyHTML() {
        let draft = RecipeDraft(
            title: "Chips & Dip",
            ingredients: ["<b>Chips</b>"]
        )

        let body = RecipeNoteFormatter.bodyHTML(for: draft)

        #expect(body.hasPrefix("<div>Chips &amp; Dip</div>"))
        #expect(body.contains("&lt;b&gt;Chips&lt;/b&gt;"))
        #expect(!body.contains("\n"))
    }
}
