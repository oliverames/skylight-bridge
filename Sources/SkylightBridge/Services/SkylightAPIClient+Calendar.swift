import Foundation

extension SkylightAPIClient {
    func listCalendarEvents(
        frameID: String,
        dateMin: String? = nil,
        dateMax: String? = nil,
        timezone: String? = nil
    ) async throws -> [SkylightResource<SkylightCalendarEventAttributes>] {
        let query = calendarEventQuery(
            dateMin: dateMin,
            dateMax: dateMax,
            timezone: timezone
        )
        let response: SkylightCollectionResponse<SkylightCalendarEventAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "calendar_events"],
            query: query
        )
        return response.data
    }

    func createCalendarEvent(
        frameID: String,
        request: SkylightCalendarEventRequest
    ) async throws -> SkylightResource<SkylightCalendarEventAttributes> {
        let response: SkylightSingleResponse<SkylightCalendarEventAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "calendar_events"],
            body: request
        )
        return response.data
    }

    func updateCalendarEvent(
        frameID: String,
        eventID: String,
        request: SkylightCalendarEventRequest
    ) async throws -> SkylightResource<SkylightCalendarEventAttributes> {
        let response: SkylightSingleResponse<SkylightCalendarEventAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "calendar_events", eventID],
            body: request
        )
        return response.data
    }

    func deleteCalendarEvent(frameID: String, eventID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "calendar_events", eventID]
        )
    }

    func searchCalendarEvents(
        frameID: String,
        query searchText: String
    ) async throws -> [SkylightResource<SkylightCalendarEventAttributes>] {
        let response: SkylightCollectionResponse<SkylightCalendarEventAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "calendar_events", "search"],
            query: [URLQueryItem(name: "query", value: searchText)]
        )
        return response.data
    }

    func listCountdownEvents(
        frameID: String
    ) async throws -> [SkylightResource<SkylightCalendarEventAttributes>] {
        let response: SkylightCollectionResponse<SkylightCalendarEventAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "calendar_events", "countdowns"]
        )
        return response.data
    }

    func listRecentInvitedEmails(frameID: String) async throws -> [String] {
        let response: SkylightStringListResponse = try await send(
            method: "GET",
            path: ["frames", frameID, "calendar_events", "recent_invited_emails"]
        )
        return response.data
    }

    func listCalendarAccounts(
        frameID: String
    ) async throws -> [SkylightResource<SkylightCalendarAccountAttributes>] {
        let response: SkylightCollectionResponse<SkylightCalendarAccountAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "calendars"]
        )
        return response.data
    }

    func getCalendarAccount(
        frameID: String,
        calendarID: String
    ) async throws -> SkylightResource<SkylightCalendarAccountAttributes> {
        let response: SkylightSingleResponse<SkylightCalendarAccountAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "calendars", calendarID]
        )
        return response.data
    }

    func listSourceCalendars(
        frameID: String
    ) async throws -> [SkylightResource<SkylightSourceCalendarAttributes>] {
        let response: SkylightCollectionResponse<SkylightSourceCalendarAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "source_calendars"]
        )
        return response.data
    }

    func getSourceCalendar(
        frameID: String,
        sourceID: String
    ) async throws -> SkylightResource<SkylightSourceCalendarAttributes> {
        let response: SkylightSingleResponse<SkylightSourceCalendarAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "source_calendars", sourceID]
        )
        return response.data
    }

    func createSourceCalendar(
        frameID: String,
        request: SkylightSourceCalendarRequest
    ) async throws -> SkylightResource<SkylightSourceCalendarAttributes> {
        let response: SkylightSingleResponse<SkylightSourceCalendarAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "source_calendars"],
            body: request
        )
        return response.data
    }

    func updateSourceCalendar(
        frameID: String,
        sourceID: String,
        request: SkylightSourceCalendarRequest
    ) async throws -> SkylightResource<SkylightSourceCalendarAttributes> {
        let response: SkylightSingleResponse<SkylightSourceCalendarAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "source_calendars", sourceID],
            body: request
        )
        return response.data
    }

    func deleteSourceCalendar(frameID: String, sourceID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "source_calendars", sourceID]
        )
    }

    private func calendarEventQuery(
        dateMin: String?,
        dateMax: String?,
        timezone: String?
    ) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if let dateMin { query.append(URLQueryItem(name: "date_min", value: dateMin)) }
        if let dateMax { query.append(URLQueryItem(name: "date_max", value: dateMax)) }
        if let timezone { query.append(URLQueryItem(name: "timezone", value: timezone)) }
        return query
    }
}
