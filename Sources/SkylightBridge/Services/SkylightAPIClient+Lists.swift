import Foundation

extension SkylightAPIClient {
    func listLists(frameID: String) async throws -> SkylightListCollectionResponse {
        try await send(method: "GET", path: ["frames", frameID, "lists"])
    }

    func getList(frameID: String, listID: String) async throws -> SkylightListDetailResponse {
        try await send(method: "GET", path: ["frames", frameID, "lists", listID])
    }

    func createList(
        frameID: String,
        request: SkylightListRequest
    ) async throws -> SkylightResource<SkylightListAttributes> {
        let effectiveRequest = SkylightListRequest(
            label: request.label,
            color: request.color ?? "#2178AF",
            kind: request.kind ?? .toDo,
            hideOnDevice: request.hideOnDevice
        )
        let response: SkylightListDetailResponse = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "lists"],
            body: effectiveRequest
        )
        return response.data
    }

    func updateList(
        frameID: String,
        listID: String,
        request: SkylightListRequest
    ) async throws -> SkylightResource<SkylightListAttributes> {
        let response: SkylightListDetailResponse = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "lists", listID],
            body: request
        )
        return response.data
    }

    func deleteList(frameID: String, listID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "lists", listID]
        )
    }

    func listListItems(
        frameID: String,
        listID: String
    ) async throws -> [SkylightResource<SkylightListItemAttributes>] {
        let response: SkylightCollectionResponse<SkylightListItemAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "lists", listID, "list_items"]
        )
        return response.data
    }

    func createListItem(
        frameID: String,
        listID: String,
        request: SkylightListItemRequest
    ) async throws -> SkylightResource<SkylightListItemAttributes> {
        let response: SkylightSingleResponse<SkylightListItemAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "lists", listID, "list_items"],
            body: request
        )
        return response.data
    }

    func updateListItem(
        frameID: String,
        listID: String,
        itemID: String,
        request: SkylightListItemRequest
    ) async throws -> SkylightResource<SkylightListItemAttributes> {
        let response: SkylightSingleResponse<SkylightListItemAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "lists", listID, "list_items", itemID],
            body: request
        )
        return response.data
    }

    func deleteListItem(frameID: String, listID: String, itemID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "lists", listID, "list_items", itemID]
        )
    }

    func moveListItem(
        frameID: String,
        listID: String,
        itemID: String,
        afterItemID: String?
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "lists", listID, "list_items", itemID, "move"],
            body: SkylightMoveListItemRequest(afterItemID: afterItemID)
        )
    }

    func bulkUpdateListSection(
        frameID: String,
        listID: String,
        itemIDs: [String],
        section: String
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "PUT",
            path: ["frames", frameID, "lists", listID, "list_items", "bulk_update_section"],
            body: SkylightBulkListSectionRequest(itemIDs: itemIDs, section: section)
        )
    }

    func bulkDeleteListItems(
        frameID: String,
        listID: String,
        itemIDs: [String]
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "lists", listID, "list_items", "bulk_destroy"],
            body: SkylightBulkListDeleteRequest(ids: itemIDs)
        )
    }

    func organizeList(frameID: String, listID: String) async throws {
        try await sendWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "lists", listID, "organize"]
        )
    }

    func orderList(
        frameID: String,
        listID: String,
        retailer: String? = nil
    ) async throws -> SkylightGroceryOrderResponse {
        try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "lists", listID, "order"],
            body: SkylightGroceryOrderRequest(retailer: retailer)
        )
    }
}
