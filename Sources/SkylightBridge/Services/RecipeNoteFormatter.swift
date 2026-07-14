import Foundation

/// Renders recipe drafts into the exact note shape `RecipeParser` reads back,
/// and decodes Skylight recipe attributes into normalized drafts.
///
/// The round trip must stay stable: a recipe pulled from Skylight becomes a
/// note whose next parse produces an equal draft, so the following push cycle
/// plans no changes.
enum RecipeNoteFormatter {
    static func plaintext(for draft: RecipeDraft) -> String {
        let blocks = [[draft.title]] + contentBlocks(for: draft, includeSource: true)
        return blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// The Skylight `description` payload for a draft. The title travels in the
    /// recipe summary and the source URL in the url field, so both are omitted.
    static func skylightDescription(for draft: RecipeDraft) -> String? {
        let blocks = contentBlocks(for: draft, includeSource: false)
        guard !blocks.isEmpty else { return nil }
        return blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    /// Notes-flavored HTML for `createNote`/`updateNote`. Notes shows the first
    /// line as the note title.
    ///
    /// Formatted bodies follow the household Apple Notes conventions: an `<h1>`
    /// title, `<h2>` section headings flowing straight into native `<ul>`/`<ol>`
    /// lists, a `<div><br></div>` spacer after every closed list and between
    /// sections, and bare URLs because Notes strips anchor tags on update. The
    /// plain variant writes one `<div>` per line for users who prefer unstyled
    /// notes.
    static func bodyHTML(for draft: RecipeDraft, formatted: Bool) -> String {
        formatted ? formattedBodyHTML(for: draft) : plainBodyHTML(for: draft)
    }

    private static func plainBodyHTML(for draft: RecipeDraft) -> String {
        plaintext(for: draft)
            .components(separatedBy: "\n")
            .map { line in
                line.isEmpty ? "<div><br></div>" : "<div>\(escapedHTML(line))</div>"
            }
            .joined()
    }

    private static func formattedBodyHTML(for draft: RecipeDraft) -> String {
        let spacer = "<div><br></div>"
        var blocks: [String] = []
        blocks.append("<h1>\(escapedHTML(draft.title))</h1>")

        let descriptionLines = (draft.description ?? "")
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        if !descriptionLines.isEmpty {
            blocks.append(descriptionLines.map { "<div>\(escapedHTML($0))</div>" }.joined())
        }

        var details: [String] = []
        if let servings = draft.servings {
            details.append(detailRow(key: "Servings", value: servings))
        }
        if let preparationTime = draft.preparationTime {
            details.append(detailRow(key: "Prep", value: preparationTime))
        }
        if let cookingTime = draft.cookingTime {
            details.append(detailRow(key: "Cook", value: cookingTime))
        }
        if !draft.tags.isEmpty {
            details.append(detailRow(key: "Tags", value: draft.tags.joined(separator: ", ")))
        }
        if let sourceURL = draft.sourceURL {
            details.append(detailRow(key: "Source", value: sourceURL))
        }
        if !details.isEmpty {
            blocks.append(details.joined())
        }

        if !draft.ingredients.isEmpty {
            let items = draft.ingredients
                .map { "<li>\(escapedHTML($0))</li>" }
                .joined()
            blocks.append("<h2>Ingredients</h2><ul>\(items)</ul>")
        }
        if !draft.instructions.isEmpty {
            let items = draft.instructions
                .map { "<li>\(escapedHTML($0))</li>" }
                .joined()
            blocks.append("<h2>Instructions</h2><ol>\(items)</ol>")
        }

        return blocks.joined(separator: spacer)
    }

    private static func detailRow(key: String, value: String) -> String {
        "<div><b>\(key):</b> \(escapedHTML(value))</div>"
    }

    /// Decodes Skylight recipe attributes into a normalized draft. Bridge-written
    /// descriptions parse back into their structured fields; freeform descriptions
    /// from the Skylight app stay as description text with the structured
    /// ingredient list merged in.
    static func draft(from attributes: SkylightRecipeAttributes) -> RecipeDraft {
        let title = (attributes.summary ?? "").trimmed
        let safeTitle = title.isEmpty ? "Untitled Recipe" : title
        let structuredIngredients = (attributes.ingredients ?? [])
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        let structuredURL = attributes.url?.trimmed
        let fallbackURL = (structuredURL?.isEmpty == false) ? structuredURL : nil

        guard let description = attributes.description?.trimmed,
              !description.isEmpty,
              let parsed = try? RecipeParser.parse("\(safeTitle)\n\(description)") else {
            return RecipeDraft(
                title: safeTitle,
                ingredients: structuredIngredients,
                sourceURL: fallbackURL
            )
        }
        return RecipeDraft(
            title: parsed.title,
            description: parsed.description,
            servings: parsed.servings,
            preparationTime: parsed.preparationTime,
            cookingTime: parsed.cookingTime,
            ingredients: parsed.ingredients.isEmpty ? structuredIngredients : parsed.ingredients,
            instructions: parsed.instructions,
            tags: parsed.tags,
            sourceURL: parsed.sourceURL ?? fallbackURL
        )
    }

    private static func contentBlocks(
        for draft: RecipeDraft,
        includeSource: Bool
    ) -> [[String]] {
        var blocks: [[String]] = []

        let descriptionLines = (draft.description ?? "")
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        if !descriptionLines.isEmpty {
            blocks.append(descriptionLines)
        }

        var details: [String] = []
        if let servings = draft.servings {
            details.append("Servings: \(servings)")
        }
        if let preparationTime = draft.preparationTime {
            details.append("Prep: \(preparationTime)")
        }
        if let cookingTime = draft.cookingTime {
            details.append("Cook: \(cookingTime)")
        }
        if !draft.tags.isEmpty {
            details.append("Tags: " + draft.tags.joined(separator: ", "))
        }
        if includeSource, let sourceURL = draft.sourceURL {
            details.append("Source: \(sourceURL)")
        }
        if !details.isEmpty {
            blocks.append(details)
        }

        if !draft.ingredients.isEmpty {
            blocks.append(["Ingredients"] + draft.ingredients.map { "- \($0)" })
        }
        if !draft.instructions.isEmpty {
            let numbered = draft.instructions.enumerated().map { index, instruction in
                "\(index + 1). \(instruction)"
            }
            blocks.append(["Instructions"] + numbered)
        }
        return blocks
    }

    private static func escapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
