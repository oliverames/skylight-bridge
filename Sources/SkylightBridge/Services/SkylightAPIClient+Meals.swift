import Foundation

extension SkylightAPIClient {
    func listMealCategories(
        frameID: String
    ) async throws -> [SkylightResource<SkylightMealCategoryAttributes>] {
        let response: SkylightCollectionResponse<SkylightMealCategoryAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "meals", "categories"]
        )
        return response.data
    }

    func updateMealCategory(
        frameID: String,
        categoryID: String,
        request: SkylightMealCategoryRequest
    ) async throws -> SkylightResource<SkylightMealCategoryAttributes> {
        let response: SkylightSingleResponse<SkylightMealCategoryAttributes> = try await sendJSON(
            method: "PATCH",
            path: ["frames", frameID, "meals", "categories", categoryID],
            body: request
        )
        return response.data
    }

    func listRecipes(frameID: String) async throws -> [SkylightResource<SkylightRecipeAttributes>] {
        let response: SkylightCollectionResponse<SkylightRecipeAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "meals", "recipes"],
            query: includeMealCategoryQuery
        )
        return response.data
    }

    func getRecipe(
        frameID: String,
        recipeID: String
    ) async throws -> SkylightResource<SkylightRecipeAttributes> {
        let response: SkylightSingleResponse<SkylightRecipeAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "meals", "recipes", recipeID],
            query: includeMealCategoryQuery
        )
        return response.data
    }

    func createRecipe(
        frameID: String,
        request: SkylightRecipeRequest
    ) async throws -> SkylightResource<SkylightRecipeAttributes> {
        let response: SkylightSingleResponse<SkylightRecipeAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "meals", "recipes"],
            query: includeMealCategoryQuery,
            body: request
        )
        return response.data
    }

    func updateRecipe(
        frameID: String,
        recipeID: String,
        request: SkylightRecipeRequest
    ) async throws -> SkylightResource<SkylightRecipeAttributes> {
        let response: SkylightSingleResponse<SkylightRecipeAttributes> = try await sendJSON(
            method: "PATCH",
            path: ["frames", frameID, "meals", "recipes", recipeID],
            query: includeMealCategoryQuery,
            body: request
        )
        return response.data
    }

    func deleteRecipe(
        frameID: String,
        recipeID: String,
        applyToSittings: Bool = true
    ) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "meals", "recipes", recipeID],
            query: [
                URLQueryItem(name: "apply_to_sittings", value: String(applyToSittings))
            ]
        )
    }

    func addRecipeToGroceryList(frameID: String, recipeID: String) async throws {
        try await sendWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "meals", "recipes", recipeID, "add_to_grocery_list"]
        )
    }

    func listMealSittings(
        frameID: String,
        dateMin: String? = nil,
        dateMax: String? = nil
    ) async throws -> [SkylightResource<SkylightMealSittingAttributes>] {
        var query: [URLQueryItem] = []
        if let dateMin { query.append(URLQueryItem(name: "date_min", value: dateMin)) }
        if let dateMax { query.append(URLQueryItem(name: "date_max", value: dateMax)) }
        let response: SkylightCollectionResponse<SkylightMealSittingAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "meals", "sittings"],
            query: query
        )
        return response.data
    }

    func createMealSitting(
        frameID: String,
        request: SkylightMealSittingRequest
    ) async throws -> SkylightResource<SkylightMealSittingAttributes> {
        let response: SkylightCollectionResponse<SkylightMealSittingAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "meals", "sittings"],
            body: request
        )
        guard let created = response.data.first else {
            throw SkylightAPIError.missingResponseBody
        }
        return created
    }

    func listMealInstances(
        frameID: String,
        mealID: String
    ) async throws -> [SkylightResource<SkylightMealSittingAttributes>] {
        let response: SkylightCollectionResponse<SkylightMealSittingAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "meals", "sittings", mealID, "instances"]
        )
        return response.data
    }

    func updateMealInstance(
        frameID: String,
        mealID: String,
        instanceISO: String,
        request: SkylightMealInstanceUpdateRequest
    ) async throws -> SkylightResource<SkylightMealSittingAttributes> {
        let response: SkylightSingleResponse<SkylightMealSittingAttributes> = try await sendJSON(
            method: "PATCH",
            path: ["frames", frameID, "meals", "sittings", mealID, "instances", instanceISO],
            body: request
        )
        return response.data
    }

    func deleteMealInstance(
        frameID: String,
        mealID: String,
        instanceISO: String,
        applyTo: String? = nil
    ) async throws {
        let query = applyTo.map { [URLQueryItem(name: "apply_to", value: $0)] } ?? []
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "meals", "sittings", mealID, "instances", instanceISO],
            query: query
        )
    }

    func migrateMealSittings(frameID: String) async throws {
        try await sendWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "meals", "sittings", "migrate"]
        )
    }

    private var includeMealCategoryQuery: [URLQueryItem] {
        [URLQueryItem(name: "include", value: "meal_category")]
    }
}
