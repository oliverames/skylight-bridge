import Foundation
import Testing
@testable import SkylightBridge

struct SecurityHardeningTests {
    @Test("Permission metadata covers Photos, Reminders, and Notes")
    func permissionMetadataCoversAppleSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let info = try propertyList(at: root.appending(path: "Resources/Info.plist"))
        let entitlements = try propertyList(
            at: root.appending(path: "Resources/SkylightBridge.entitlements")
        )

        #expect((info["NSPhotoLibraryUsageDescription"] as? String)?.isEmpty == false)
        #expect((info["NSRemindersFullAccessUsageDescription"] as? String)?.isEmpty == false)
        #expect((info["NSAppleEventsUsageDescription"] as? String)?.isEmpty == false)
        #expect(entitlements["com.apple.security.personal-information.photos-library"] as? Bool == true)
        #expect(entitlements["com.apple.security.personal-information.calendars"] as? Bool == true)
        #expect(entitlements["com.apple.security.automation.apple-events"] as? Bool == true)
    }

    @Test("Changing the account email invalidates the previous OAuth session")
    func accountSwitchInvalidatesTokens() {
        #expect(SkylightSessionManager.shouldInvalidateTokens(
            storedEmail: "first@example.com",
            replacementEmail: "second@example.com"
        ))
        #expect(!SkylightSessionManager.shouldInvalidateTokens(
            storedEmail: " Person@Example.com ",
            replacementEmail: "person@example.com"
        ))
    }

    @Test("Photo uploads require a public HTTPS object-storage destination")
    func validatesPhotoUploadDestinations() throws {
        let accepted = try SkylightAPIClient.validatedUploadURL(
            "https://example-bucket.s3.us-east-1.amazonaws.com/photo.jpg?signature=temporary"
        )
        #expect(accepted.scheme == "https")

        let rejected = [
            "http://example-bucket.s3.amazonaws.com/photo.jpg",
            "https://127.0.0.1/internal",
            "https://169.254.169.254/latest/meta-data",
            "https://user@example-bucket.s3.amazonaws.com/photo.jpg",
            "https://example.invalid:8443/photo.jpg"
        ]
        for value in rejected {
            do {
                _ = try SkylightAPIClient.validatedUploadURL(value)
                Issue.record("Expected upload destination to be rejected: \(value)")
            } catch is SkylightAPIError {
                // Expected.
            }
        }
    }

    @Test("Network error descriptions never expose response bodies")
    func redactsNetworkErrorBodies() {
        let api = SkylightAPIError.httpStatus(code: 401, body: "refresh_token=secret")
        let oauth = SkylightOAuthError.invalidFormResponse(
            statusCode: 400,
            body: "authorization_code=secret"
        )

        #expect(!api.localizedDescription.contains("secret"))
        #expect(!oauth.localizedDescription.contains("secret"))
    }

    @Test("Structured validation errors surface without echoing the raw body")
    func surfacesValidationDetailSafely() {
        let validation = SkylightAPIError.httpStatus(
            code: 422,
            body: #"{"errors":{"instance_date":["must be blank"]}}"#
        )
        #expect(validation.localizedDescription.contains("instance_date: must be blank"))

        // A JSON error body that reflects a secret value is still not echoed,
        // because only the `errors` envelope is read.
        let leaky = SkylightAPIError.httpStatus(
            code: 401,
            endpoint: "/oauth/token",
            body: #"{"access_token":"secret","message":"secret"}"#
        )
        #expect(!leaky.localizedDescription.contains("secret"))
        #expect(leaky.localizedDescription == "Skylight request to /oauth/token returned HTTP 401.")
    }

    @Test("Malformed meal plans fail closed instead of looking empty")
    func malformedMealPlanFailsClosed() {
        do {
            _ = try MealPlanParser.parse("not a meal plan")
            Issue.record("Expected malformed meal content to be rejected")
        } catch is MealPlanParserError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Recipe and meal parsing enforce bounded inputs")
    func parsersEnforceBounds() {
        let oversized = String(repeating: "x", count: 1_048_577)

        do {
            _ = try RecipeParser.parse(oversized)
            Issue.record("Expected oversized recipe to be rejected")
        } catch is RecipeParserError {
            // Expected.
        } catch {
            Issue.record("Unexpected recipe error: \(error)")
        }

        do {
            _ = try MealPlanParser.parse(oversized)
            Issue.record("Expected oversized meal plan to be rejected")
        } catch is MealPlanParserError {
            // Expected.
        } catch {
            Issue.record("Unexpected meal error: \(error)")
        }
    }

    @Test("Signed local files reject tampering")
    func signedLocalFileRejectsTampering() throws {
        let authenticator = LocalFileAuthenticator(testKey: Data(repeating: 0x2A, count: 32))
        let configuration = AppConfiguration.empty
        let encoded = try authenticator.seal(configuration)
        let decoded = try authenticator.open(AppConfiguration.self, from: encoded)
        #expect(decoded == configuration)

        var tampered = encoded
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        do {
            _ = try authenticator.open(AppConfiguration.self, from: tampered)
            Issue.record("Expected tampered local state to be rejected")
        } catch is LocalFileIntegrityError {
            // Expected.
        }
    }

    @Test("Signed local files preserve fractional-second sync timestamps")
    func signedLocalFilePreservesDatePrecision() throws {
        let authenticator = LocalFileAuthenticator(testKey: Data(repeating: 0x31, count: 32))
        let original = PreciseDatePayload(
            date: Date(timeIntervalSince1970: 1_750_000_000.654_321)
        )

        let encoded = try authenticator.seal(original)
        let decoded = try authenticator.open(PreciseDatePayload.self, from: encoded)

        #expect(abs(decoded.date.timeIntervalSince(original.date)) < 0.000_001)
    }
}

private struct PreciseDatePayload: Codable {
    let date: Date
}
