import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SkylightBridge

struct LiveSkylightIntegrationTests {
    @Test("Live account supports authentication, read, list, and photo lifecycle")
    func liveAccountLifecycle() async throws {
        guard let email = ProcessInfo.processInfo.environment["SKYLIGHT_EMAIL"],
              let password = ProcessInfo.processInfo.environment["SKYLIGHT_PASSWORD"],
              !email.isEmpty,
              !password.isEmpty else {
            return
        }

        let fingerprint = "skylight-bridge-integration-\(UUID().uuidString.lowercased())"
        let authenticator = SkylightOAuthAuthenticator(deviceFingerprint: fingerprint)
        let token = try await authenticator.login(email: email, password: password)
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

    private func currentISODate() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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
    case imageCreationFailed
    case processingTimedOut(String?)
    case albumMembershipTimedOut
    case invalidAssetType
}
