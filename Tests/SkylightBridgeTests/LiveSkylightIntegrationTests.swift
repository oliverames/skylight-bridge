import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SkylightBridge

private let liveChoreMutationsEnabled =
    ProcessInfo.processInfo.environment["SKYLIGHT_LIVE_CHORE_MUTATIONS"] == "1"
private let liveReadsEnabled =
    ProcessInfo.processInfo.environment["SKYLIGHT_LIVE_READS"] == "1"
private let liveSkylightCredentials: (email: String, password: String)? = {
    guard ProcessInfo.processInfo.environment["SKYLIGHT_LIVE_TESTS"] == "1",
          let email = ProcessInfo.processInfo.environment["SKYLIGHT_EMAIL"],
          let password = ProcessInfo.processInfo.environment["SKYLIGHT_PASSWORD"],
          !email.isEmpty,
          !password.isEmpty else { return nil }
    return (email, password)
}()

struct LiveSkylightIntegrationTests {
    @Test(
        "Live recurring chore create, complete, reopen, and delete lifecycle",
        .enabled(
            if: liveChoreMutationsEnabled,
            "Set SKYLIGHT_LIVE_CHORE_MUTATIONS=1 to run this mutating live test."
        )
    )
    func liveRecurringChoreLifecycle() async throws {
        let manager = SkylightSessionManager()
        let client = try await manager.client(
            configuration: SkylightAccountConfiguration(),
            validateFrame: false
        )
        let frame = try #require(try await client.listFrames().first)
        let category = try #require(
            try await client.listCategories(frameID: frame.id).first {
                $0.attributes.selectedForChoreChart == true
            }
        )
        for leftover in try await client.listAllChores(frameID: frame.id)
        where (leftover.attributes.summary ?? "").hasPrefix("Skylight Bridge Verification") {
            try await client.deleteChore(
                frameID: frame.id,
                choreID: leftover.attributes.series ?? leftover.id
            )
        }
        let today = currentISODate()
        var seriesID: String?
        do {
            let created = try await client.createRoutineChore(
                frameID: frame.id,
                request: SkylightChoreRequest(
                    summary: "Skylight Bridge Verification \(UUID().uuidString.prefix(8))",
                    description: "Temporary integration test; safe to delete.",
                    start: today,
                    categoryID: category.id,
                    categoryIDs: [category.id],
                    recurring: true,
                    recurrenceSet: ["RRULE:FREQ=DAILY;INTERVAL=1;BYHOUR=6"],
                    upForGrabs: false,
                    routine: true
                )
            )
            seriesID = created.attributes.series ?? created.id
            let resolvedID = try #require(seriesID)
            _ = try await client.updateChore(
                frameID: frame.id,
                choreID: resolvedID,
                request: SkylightChoreRequest(
                    summary: "Skylight Bridge Verification Updated",
                    description: "Temporary integration test; safe to delete.",
                    start: today,
                    categoryID: category.id,
                    categoryIDs: [category.id],
                    recurring: true,
                    recurrenceSet: ["RRULE:FREQ=DAILY;INTERVAL=1;BYHOUR=6"],
                    upForGrabs: false,
                    routine: true
                )
            )
            let inventory = try await client.listAllChores(frameID: frame.id)
            #expect(inventory.contains { ($0.attributes.series ?? $0.id) == resolvedID })
            try await client.setChoreCompletion(
                frameID: frame.id,
                seriesID: resolvedID,
                request: SkylightChoreCompletionRequest(
                    status: .complete,
                    instanceDate: today,
                    instanceTime: "06:00"
                )
            )
            try await client.setChoreCompletion(
                frameID: frame.id,
                seriesID: resolvedID,
                request: SkylightChoreCompletionRequest(
                    status: .pending,
                    instanceDate: today,
                    instanceTime: "06:00"
                )
            )
            try await client.deleteChore(frameID: frame.id, choreID: resolvedID)
            try await waitForChoreDeletion(
                client: client,
                frameID: frame.id,
                seriesID: resolvedID
            )
            try await waitForChoreVerificationCleanup(client: client, frameID: frame.id)
            seriesID = nil
        } catch {
            if let seriesID {
                try? await client.deleteChore(frameID: frame.id, choreID: seriesID)
            }
            throw error
        }
    }

    @Test(
        "Live chore inventory matches the sync decoder contract",
        .enabled(
            if: liveReadsEnabled,
            "Set SKYLIGHT_LIVE_READS=1 to run this live account read."
        )
    )
    func liveChoreInventoryContract() async throws {
        let manager = SkylightSessionManager()
        let client = try await manager.client(
            configuration: SkylightAccountConfiguration(),
            validateFrame: false
        )
        let frame = try #require(try await client.listFrames().first)
        let categories = try await client.listCategories(frameID: frame.id)
        let chores: [SkylightResource<SkylightChoreAttributes>]
        do {
            chores = try await client.listAllChores(frameID: frame.id)
        } catch {
            let raw: SkylightJSONValue = try await client.authenticatedRequest(
                method: "GET",
                path: ["frames", frame.id, "chores", "all"]
            )
            print("CHORE_RAW_SHAPE \(Self.jsonShape(raw))")
            throw error
        }
        let relationshipKeys = Set(chores.flatMap { $0.relationships?.keys ?? [:].keys })
        let recurrenceSamples = chores.compactMap(\.attributes.recurrenceSet).flatMap { $0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let before = currentISODate(calendar.date(byAdding: .day, value: 1, to: start)!)
        let after = currentISODate(calendar.date(byAdding: .day, value: -1, to: start)!)
        let datedChores = try await client.listChores(
            frameID: frame.id,
            before: before,
            after: after
        )

        print("CHORE_CONTRACT categories=\(categories.count) chores=\(chores.count) dated=\(datedChores.count) relationshipKeys=\(relationshipKeys.sorted()) recurrenceSamples=\(recurrenceSamples.prefix(3))")
        #expect(categories.contains { $0.attributes.selectedForChoreChart == true })
        if chores.contains(where: { $0.attributes.upForGrabs != true }) {
            #expect(
                relationshipKeys.contains("category")
                    || relationshipKeys.contains("categories")
                    || chores.contains { ($0.attributes.group ?? "").isEmpty == false }
            )
        }
        for rule in recurrenceSamples where rule.uppercased().hasPrefix("RRULE:")
            || rule.uppercased().hasPrefix("FREQ=") {
            _ = try RecurrenceRuleConverter.parse(rule)
        }
    }

    private static func jsonShape(_ value: SkylightJSONValue) -> String {
        switch value {
        case let .object(object):
            return "object(keys=\(object.keys.sorted()), children=\(object.mapValues(jsonShape)))"
        case let .array(array):
            return "array(count=\(array.count), first=\(array.first.map(jsonShape) ?? "none"))"
        case .string: return "string"
        case .number: return "number"
        case .bool: return "bool"
        case .null: return "null"
        }
    }

    @Test(
        "Live account supports authentication, read, list, and photo lifecycle",
        .enabled(
            if: liveSkylightCredentials != nil,
            "Set SKYLIGHT_LIVE_TESTS=1 with SKYLIGHT_EMAIL and SKYLIGHT_PASSWORD."
        )
    )
    func liveAccountLifecycle() async throws {
        let credentials = try #require(liveSkylightCredentials)

        let fingerprint = "skylight-bridge-integration-\(UUID().uuidString.lowercased())"
        let authenticator = SkylightOAuthAuthenticator(deviceFingerprint: fingerprint)
        let token = try await authenticator.login(
            email: credentials.email,
            password: credentials.password
        )
        let client = SkylightAPIClient(accessToken: token.accessToken)
        let frames = try await client.listFrames()
        let frame = try #require(frames.first)

        _ = try await client.getFrame(frameID: frame.id)
        _ = try await client.listDevices(frameID: frame.id)
        _ = try await client.getPlusAccess()

        let suffix = UUID().uuidString.prefix(8)
        var listID: String?
        var itemID: String?
        var albumID: String?
        var messageID: String?
        var recipeID: String?
        var mealID: String?
        var mealInstanceISO: String?

        do {
            let list = try await client.createList(
                frameID: frame.id,
                request: SkylightListRequest(
                    label: "Skylight Bridge Integration \(suffix)",
                    kind: .other,
                    hideOnDevice: true
                )
            )
            listID = list.id
            _ = try await client.getList(frameID: frame.id, listID: list.id)
            let item = try await client.createListItem(
                frameID: frame.id,
                listID: list.id,
                request: SkylightListItemRequest(label: "Temporary verification item", status: .pending)
            )
            itemID = item.id
            _ = try await client.updateListItem(
                frameID: frame.id,
                listID: list.id,
                itemID: item.id,
                request: SkylightListItemRequest(label: "Temporary verified item", status: .completed)
            )
            try await client.deleteListItem(frameID: frame.id, listID: list.id, itemID: item.id)
            itemID = nil
            try await client.deleteList(frameID: frame.id, listID: list.id)
            listID = nil

            let album = try await client.createAlbum(
                frameID: frame.id,
                title: "Skylight Bridge Integration \(suffix)"
            )
            albumID = album.id
            let uploadCaption = "Skylight Bridge Integration \(suffix)"
            let upload = try await client.requestUploadURL(
                ext: "jpg",
                frameIDs: [frame.id],
                caption: uploadCaption
            )
            let uploadURL = try #require(URL(string: upload.url))
            let uploadedMessageID = try #require(upload.messageIDs?.first)
            messageID = uploadedMessageID
            try await client.upload(data: try testJPEG(), to: uploadURL, contentType: "image/jpeg")
            let resolvedMessageID = try await waitForMessage(
                client: client,
                frameID: frame.id,
                expectedMessageID: uploadedMessageID,
                caption: uploadCaption
            )
            messageID = resolvedMessageID
            try await client.addMessages(
                frameID: frame.id,
                albumIDs: [album.id],
                messageIDs: [resolvedMessageID]
            )
            try await waitForAlbumMembership(
                client: client,
                frameID: frame.id,
                albumID: album.id,
                messageID: resolvedMessageID
            )
            try await client.removeMessages(
                frameID: frame.id,
                albumIDs: [album.id],
                messageIDs: [resolvedMessageID]
            )
            try await client.deleteMessage(frameID: frame.id, messageID: resolvedMessageID)
            messageID = nil
            try await client.deleteAlbum(frameID: frame.id, albumID: album.id)
            albumID = nil

            let recipe = try await client.createRecipe(
                frameID: frame.id,
                request: SkylightRecipeRequest(
                    mealCategoryID: try #require(
                        try await client.listMealCategories(frameID: frame.id).first?.id
                    ),
                    summary: "Skylight Bridge Integration \(suffix)",
                    description: "Temporary integration verification recipe.",
                    ingredients: ["1 verification ingredient"]
                )
            )
            recipeID = recipe.id
            let recipes = try await client.listRecipes(frameID: frame.id)
            #expect(recipes.contains(where: { $0.id == recipe.id }))

            let date = currentISODate()
            let mealCategoryID = try #require(
                try await client.listMealCategories(frameID: frame.id).first?.id
            )
            let meal = try await client.createMealSitting(
                frameID: frame.id,
                request: SkylightMealSittingRequest(
                    date: date,
                    mealRecipeID: recipe.id,
                    mealCategoryID: mealCategoryID,
                    addToGroceryList: false
                )
            )
            mealID = meal.id
            mealInstanceISO = meal.attributes.date ?? date
            try await client.deleteMealInstance(
                frameID: frame.id,
                mealID: meal.id,
                instanceISO: meal.attributes.date ?? date
            )
            mealID = nil
            mealInstanceISO = nil
            try await client.deleteRecipe(
                frameID: frame.id,
                recipeID: recipe.id,
                applyToSittings: false
            )
            recipeID = nil
        } catch {
            if let itemID, let listID {
                try? await client.deleteListItem(frameID: frame.id, listID: listID, itemID: itemID)
            }
            if let listID {
                try? await client.deleteList(frameID: frame.id, listID: listID)
            }
            if let messageID {
                try? await client.deleteMessage(frameID: frame.id, messageID: messageID)
            }
            if let albumID {
                try? await client.deleteAlbum(frameID: frame.id, albumID: albumID)
            }
            if let mealID, let mealInstanceISO {
                try? await client.deleteMealInstance(
                    frameID: frame.id,
                    mealID: mealID,
                    instanceISO: mealInstanceISO
                )
            }
            if let recipeID {
                try? await client.deleteRecipe(
                    frameID: frame.id,
                    recipeID: recipeID,
                    applyToSittings: false
                )
            }
            throw error
        }
    }

    private func testJPEG() throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: 640,
            height: 360,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw LiveTestError.imageCreationFailed
        }
        context.setFillColor(red: 0.12, green: 0.42, blue: 0.72, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        guard let image = context.makeImage() else {
            throw LiveTestError.imageCreationFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LiveTestError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LiveTestError.imageCreationFailed
        }
        return data as Data
    }

    private func currentISODate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func waitForChoreDeletion(
        client: SkylightAPIClient,
        frameID: String,
        seriesID: String
    ) async throws {
        for _ in 0 ..< 20 {
            let inventory = try await client.listAllChores(frameID: frameID)
            if !inventory.contains(where: { ($0.attributes.series ?? $0.id) == seriesID }) {
                return
            }
            try await ContinuousClock().sleep(for: .milliseconds(250))
        }
        throw LiveTestError.choreDeletionTimedOut(seriesID)
    }

    private func waitForChoreVerificationCleanup(
        client: SkylightAPIClient,
        frameID: String
    ) async throws {
        for _ in 0 ..< 20 {
            let leftovers = try await client.listAllChores(frameID: frameID).filter {
                ($0.attributes.summary ?? "").hasPrefix("Skylight Bridge Verification")
            }
            if leftovers.isEmpty {
                return
            }
            try await ContinuousClock().sleep(for: .milliseconds(250))
        }
        throw LiveTestError.choreVerificationCleanupTimedOut
    }

    private func waitForMessage(
        client: SkylightAPIClient,
        frameID: String,
        expectedMessageID: String,
        caption: String
    ) async throws -> String {
        var lastStatus: String?
        for _ in 0..<40 {
            if let response = try? await client.listMessages(
                frameID: frameID,
                pageToken: "__START__"
            ), let message = response.data.first(where: {
                $0.id == expectedMessageID || $0.attributes.caption == caption
            }) {
                lastStatus = message.attributes.status
                switch message.attributes.status {
                case "awaiting_download", "downloaded":
                    return message.id
                case "invalid_asset_type":
                    throw LiveTestError.invalidAssetType
                default:
                    break
                }
            }
            try await ContinuousClock().sleep(for: .milliseconds(500))
        }
        throw LiveTestError.processingTimedOut(lastStatus)
    }

    private func waitForAlbumMembership(
        client: SkylightAPIClient,
        frameID: String,
        albumID: String,
        messageID: String
    ) async throws {
        for _ in 0..<20 {
            let ids = try await client.listAllAlbumMessageIDs(frameID: frameID, albumID: albumID)
            if ids.contains(messageID) { return }
            try await ContinuousClock().sleep(for: .milliseconds(500))
        }
        throw LiveTestError.albumMembershipTimedOut
    }
}

private enum LiveTestError: Error {
    case choreDeletionTimedOut(String)
    case choreVerificationCleanupTimedOut
    case imageCreationFailed
    case processingTimedOut(String?)
    case albumMembershipTimedOut
    case invalidAssetType
}
