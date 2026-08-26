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

    @Test("A Skylight summary with embedded newlines stays a single-line title")
    func collapsesNewlinesInSummary() throws {
        let attributes = SkylightRecipeAttributes(
            summary: "Chocolate Cake\nServings: 999",
            description: "Rich and dark.",
            ingredients: nil,
            url: nil,
            imageURL: nil,
            createdAt: nil,
            updatedAt: nil
        )

        let draft = RecipeNoteFormatter.draft(from: attributes)

        #expect(draft.title == "Chocolate Cake Servings: 999")
        #expect(draft.servings == nil)
        #expect(draft.description == "Rich and dark.")
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

    @Test("Plain note bodies escape HTML and keep one line per div")
    func rendersPlainBodyHTML() {
        let draft = RecipeDraft(
            title: "Chips & Dip",
            ingredients: ["<b>Chips</b>"]
        )

        let body = RecipeNoteFormatter.bodyHTML(for: draft, formatted: false)

        #expect(body.hasPrefix("<div>Chips &amp; Dip</div>"))
        #expect(body.contains("&lt;b&gt;Chips&lt;/b&gt;"))
        #expect(!body.contains("\n"))
    }

    @Test("Formatted note bodies follow the Apple Notes conventions")
    func rendersFormattedBodyHTML() {
        let draft = RecipeDraft(
            title: "Tacos & Chips",
            description: "Family favorite",
            servings: "6",
            ingredients: ["Shells"],
            instructions: ["Fill the shells."],
            sourceURL: "https://example.com/tacos"
        )

        let body = RecipeNoteFormatter.bodyHTML(for: draft, formatted: true)

        #expect(body.hasPrefix("<h1>Tacos &amp; Chips</h1><div><br></div>"))
        #expect(body.contains("<div><b>Servings:</b> 6</div>"))
        #expect(body.contains("<h2>Ingredients</h2><ul><li>Shells</li></ul><div><br></div>"))
        #expect(body.contains("<h2>Instructions</h2><ol><li>Fill the shells.</li></ol>"))
        // Bare URLs, because Notes strips anchor tags on update.
        #expect(body.contains("<div><b>Source:</b> https://example.com/tacos</div>"))
        #expect(!body.contains("<a href"))
    }
}
