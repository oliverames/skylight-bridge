import Foundation

extension SkylightAPIClient {
    func listChores(
        frameID: String,
        before: String? = nil,
        after: String? = nil,
        includeLate: Bool? = nil,
        filter: String? = nil
    ) async throws -> [SkylightResource<SkylightChoreAttributes>] {
        let query = choreQuery(
            before: before,
            after: after,
            includeLate: includeLate,
            filter: filter
        )
        let response: SkylightCollectionResponse<SkylightChoreAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "chores"],
            query: query
        )
        return response.data
    }

    func listAllChores(frameID: String) async throws -> [SkylightResource<SkylightChoreAttributes>] {
        let response: SkylightAllChoresResponse = try await send(
            method: "GET",
            path: ["frames", frameID, "chores", "all"]
        )
        return response.data
    }

    func searchChores(
        frameID: String,
        query searchText: String
    ) async throws -> [SkylightResource<SkylightChoreAttributes>] {
        let response: SkylightCollectionResponse<SkylightChoreAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "chores", "search"],
            query: [URLQueryItem(name: "query", value: searchText)]
        )
        return response.data
    }

    func createChore(
        frameID: String,
        request: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes> {
        let response: SkylightSingleResponse<SkylightChoreAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "chores"],
            body: request
        )
        return response.data
    }

    func createChores(
        frameID: String,
        requests: [SkylightChoreRequest]
    ) async throws -> [SkylightResource<SkylightChoreAttributes>] {
        let response: SkylightCollectionResponse<SkylightChoreAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "chores", "create_multiple"],
            body: SkylightChoreBatchRequest(chores: requests)
        )
        return response.data
    }

    func createRoutineChore(
        frameID: String,
        request: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes> {
        let routineRequest = SkylightChoreRequest(
            summary: request.summary,
            description: request.description,
            start: request.start,
            startTime: request.startTime,
            rewardPoints: request.rewardPoints,
            status: request.status,
            categoryID: request.categoryID,
            categoryIDs: request.categoryIDs,
            recurring: request.recurring,
            recurrenceSet: request.recurrenceSet,
            recurringUntil: request.recurringUntil,
            upForGrabs: request.upForGrabs,
            emojiIcon: request.emojiIcon,
            routine: true,
            position: request.position
        )
        return try await createChore(frameID: frameID, request: routineRequest)
    }

    func updateChore(
        frameID: String,
        choreID: String,
        request: SkylightChoreRequest
    ) async throws -> SkylightResource<SkylightChoreAttributes> {
        let response: SkylightSingleResponse<SkylightChoreAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "chores", choreID],
            body: request
        )
        return response.data
    }

    /// Deletes a chore. Recurring chores must be removed with `apply_to=all` to
    /// clear the whole series; one-off chores reject that parameter (HTTP 400),
    /// so the caller passes `applyToAll: false` for them.
    func deleteChore(frameID: String, choreID: String, applyToAll: Bool = true) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "chores", choreID],
            query: applyToAll ? [URLQueryItem(name: "apply_to", value: "all")] : []
        )
    }

    func setChoreCompletion(
        frameID: String,
        seriesID: String,
        request: SkylightChoreCompletionRequest
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "PUT",
            path: ["frames", frameID, "chores", seriesID, "completions"],
            body: request
        )
    }

    func moveChore(
        frameID: String,
        choreID: String,
        before: String? = nil,
        after: String? = nil
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "chores", choreID, "move"],
            body: SkylightChoreMoveRequest(
                position: SkylightChoreMovePosition(before: before, after: after)
            )
        )
    }

    func listTaskBoxItems(
        frameID: String
    ) async throws -> [SkylightResource<SkylightTaskBoxItemAttributes>] {
        let response: SkylightCollectionResponse<SkylightTaskBoxItemAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "task_box", "items"]
        )
        return response.data
    }

    func createTaskBoxItem(
        frameID: String,
        request: SkylightTaskBoxItemRequest
    ) async throws -> SkylightResource<SkylightTaskBoxItemAttributes> {
        let response: SkylightSingleResponse<SkylightTaskBoxItemAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "task_box", "items"],
            body: request
        )
        return response.data
    }

    func updateTaskBoxItem(
        frameID: String,
        itemID: String,
        request: SkylightTaskBoxItemRequest
    ) async throws -> SkylightResource<SkylightTaskBoxItemAttributes> {
        let response: SkylightSingleResponse<SkylightTaskBoxItemAttributes> = try await sendJSON(
            method: "PATCH",
            path: ["frames", frameID, "task_box", "items", itemID],
            body: request
        )
        return response.data
    }

    func deleteTaskBoxItem(frameID: String, itemID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "task_box", "items", itemID]
        )
    }

    func listRewards(frameID: String) async throws -> [SkylightResource<SkylightRewardAttributes>] {
        let response: SkylightCollectionResponse<SkylightRewardAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "rewards"]
        )
        return response.data
    }

    func getReward(
        frameID: String,
        rewardID: String
    ) async throws -> SkylightResource<SkylightRewardAttributes> {
        let response: SkylightSingleResponse<SkylightRewardAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "rewards", rewardID]
        )
        return response.data
    }

    func createRewards(
        frameID: String,
        requests: [SkylightRewardRequest]
    ) async throws -> [SkylightResource<SkylightRewardAttributes>] {
        let response: SkylightCollectionResponse<SkylightRewardAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "rewards"],
            body: requests
        )
        return response.data
    }

    func updateReward(
        frameID: String,
        rewardID: String,
        request: SkylightRewardRequest
    ) async throws -> SkylightResource<SkylightRewardAttributes> {
        let response: SkylightSingleResponse<SkylightRewardAttributes> = try await sendJSON(
            method: "PATCH",
            path: ["frames", frameID, "rewards", rewardID],
            body: request
        )
        return response.data
    }

    func deleteReward(frameID: String, rewardID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "rewards", rewardID]
        )
    }

    func redeemReward(frameID: String, rewardID: String) async throws {
        try await sendWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "rewards", rewardID, "redeem"]
        )
    }

    func unredeemReward(frameID: String, rewardID: String) async throws {
        try await sendWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "rewards", rewardID, "unredeem"]
        )
    }

    func getRewardPoints(frameID: String) async throws -> [SkylightRewardPoint] {
        try await send(method: "GET", path: ["frames", frameID, "reward_points"])
    }

    func adjustRewardPoints(
        frameID: String,
        categoryIDs: [Int],
        points: Int
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "reward_points"],
            body: SkylightRewardPointAdjustment(categoryIDs: categoryIDs, points: points)
        )
    }

    private func choreQuery(
        before: String?,
        after: String?,
        includeLate: Bool?,
        filter: String?
    ) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if let before { query.append(URLQueryItem(name: "before", value: before)) }
        if let after { query.append(URLQueryItem(name: "after", value: after)) }
        if let includeLate {
            query.append(URLQueryItem(name: "include_late", value: String(includeLate)))
        }
        if let filter { query.append(URLQueryItem(name: "filter", value: filter)) }
        return query
    }
}
