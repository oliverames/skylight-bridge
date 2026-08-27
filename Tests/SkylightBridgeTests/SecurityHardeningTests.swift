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
        let api = SkylightAPIError.httpStatus(
            code: 401,
            endpoint: "/oauth/token",
            body: "refresh_token=secret"
        )
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
            endpoint: "/chores/123",
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

    @Test("AMFI-disabling boot arguments are detected")
    func detectsAMFIDisablingBootArguments() {
        let homeServerArguments =
            "-arm64e_preview_abi amfi_get_out_of_my_way=1 ipc_control_port_options=0"
        #expect(
            SystemSecurityDiagnostics.amfiDisablingBootArguments(in: homeServerArguments)
                == ["amfi_get_out_of_my_way=1"]
        )
        #expect(
            SystemSecurityDiagnostics.amfiDisablingBootArguments(in: "amfi=0xff cs_enforcement_disable=1")
                == ["amfi=0xff", "cs_enforcement_disable=1"]
        )
        #expect(SystemSecurityDiagnostics.amfiDisablingBootArguments(in: "").isEmpty)
        #expect(SystemSecurityDiagnostics.amfiDisablingBootArguments(in: "-v keepsyms=1").isEmpty)
        // A name that merely contains "amfi" must not match.
        #expect(SystemSecurityDiagnostics.amfiDisablingBootArguments(in: "notamfi=1 amfitest=1").isEmpty)
    }

    @Test("Blocked-consent explanation appears only for AMFI-disabling boot arguments")
    func blockedConsentExplanationGating() throws {
        #expect(SystemSecurityDiagnostics.blockedConsentPromptExplanation(bootArguments: "-v") == nil)
        let explanation = try #require(
            SystemSecurityDiagnostics.blockedConsentPromptExplanation(
                bootArguments: "amfi_get_out_of_my_way=1"
            )
        )
        #expect(explanation.contains("amfi_get_out_of_my_way=1"))
        #expect(explanation.contains("restart"))
    }

    @Test("Permission-grant script targets the app's own identity and services")
    func permissionGrantScriptContents() {
        let script = SystemSecurityDiagnostics.permissionGrantScript(
            bundleIdentifier: "com.oliverames.SkylightBridge",
            bundlePath: "/Applications/Skylight Bridge.app"
        )
        // Grants the three Apple sources the app uses, for its own bundle ID.
        #expect(script.contains("kTCCServiceReminders"))
        #expect(script.contains("kTCCServicePhotos"))
        #expect(script.contains("kTCCServiceAppleEvents"))
        #expect(script.contains("'com.apple.Notes'"))
        #expect(script.contains("'com.oliverames.SkylightBridge'"))
        #expect(script.contains("/Applications/Skylight Bridge.app"))
        // Only ever grants (auth_value=2), never denies, and reloads tccd.
        #expect(script.contains("killall tccd"))
        #expect(!script.contains("DELETE"))
    }

    @Test("Permission-grant script quotes paths before the shell can expand them")
    func permissionGrantScriptQuotesHostilePath() throws {
        let bundleIdentifier = "com.example.o'malley"
        let bundlePath = "/Applications/$(printf shell-expanded).app"
        let script = SystemSecurityDiagnostics.permissionGrantScript(
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath
        )

        #expect(script.contains("APP='/Applications/$(printf shell-expanded).app'"))
        #expect(!script.contains("APP=\"/Applications/$(printf"))
        #expect(script.contains("VALUES('$SVC','$BUNDLE_ID_SQL'"))

        let lines = script.split(separator: "\n").map(String.init)
        let appAssignment = try #require(lines.first { $0.hasPrefix("APP=") })
        let bundleAssignment = try #require(lines.first { $0.hasPrefix("BUNDLE_ID_SQL=") })
        let appOutput = try shellOutput("""
        \(appAssignment)
        printf '%s' "$APP"
        """)
        let sqlOutput = try shellOutput("""
        \(bundleAssignment)
        /usr/bin/sqlite3 :memory: "CREATE TABLE access(client TEXT); INSERT INTO access VALUES('$BUNDLE_ID_SQL'); SELECT client FROM access;"
        """)

        #expect(appOutput == bundlePath)
        #expect(sqlOutput == "\(bundleIdentifier)\n")
    }

    @Test("Sync-state writes reject files that the reader would reject")
    func syncStateWriteLimitIsSymmetric() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SyncStateStore(
            rootURL: directory,
            authenticator: LocalFileAuthenticator(testKey: Data(repeating: 0x72, count: 32))
        )
        var baseline = SyncState()
        baseline.photos = [PhotoSyncRecord(
            mappingID: UUID(), frameID: "frame-1", appleAssetID: "asset-1",
            renderedHash: "small", skylightMessageID: "message-1",
            skylightAlbumIDs: [],
            lastSyncedAt: .distantPast
        )]
        try await store.save(baseline)

        var oversized = baseline
        oversized.photos[0].renderedHash = String(repeating: "x", count: 4_300_000)
        do {
            try await store.save(oversized)
            Issue.record("Expected oversized sync state to be rejected")
        } catch let error as LocalPersistenceError {
            #expect(error == .fileTooLarge(label: "sync state", maximumBytes: 4_194_304))
            #expect(error.localizedDescription.contains("safety limit"))
            #expect(!error.localizedDescription.contains("space"))
        }

        let loaded = try await store.load()
        #expect(loaded.photos == baseline.photos)
    }

    @Test("Activity writes reject files that the reader would reject")
    func activityWriteLimitIsSymmetric() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x73, count: 32)
            ),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x74, count: 32)
            )
        )
        let baseline = [ActivityEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            date: Date(timeIntervalSince1970: 500.25),
            level: .info,
            area: .system,
            message: "Existing activity"
        )]
        try store.saveActivity(baseline)
        let oversized = (0..<500).map { index in
            ActivityEntry(
                level: .error,
                area: .system,
                message: "\(index)" + String(repeating: "🔒", count: 1_000)
            )
        }

        do {
            try store.saveActivity(oversized)
            Issue.record("Expected oversized activity history to be rejected")
        } catch let error as LocalPersistenceError {
            #expect(error == .fileTooLarge(
                label: "activity history",
                maximumBytes: 2_097_152
            ))
        }

        #expect(try store.loadActivity() == baseline)
    }

    @Test("A failed mapping save stays local and rolls back memory")
    @MainActor
    func failedMappingSaveRollsBack() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ConfigurationStore(
            rootURL: directory,
            configurationAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x75, count: 32)
            ),
            activityAuthenticator: LocalFileAuthenticator(
                testKey: Data(repeating: 0x76, count: 32)
            )
        )
        try persistence.saveConfiguration(.empty)
        let store = AppStore(persistence: persistence)
        var mapping = PhotoMapping(name: "Oversized", sourceKind: .selectedPhotos)
        mapping.selectedAssetIDs = ["asset-1"]
        mapping.selectedPhotoNames = [
            "asset-1": String(repeating: "x", count: 4_300_000)
        ]

        let saved = store.savePhotoMapping(mapping, triggerSync: true)

        #expect(!saved)
        #expect(store.configuration.photoMappings.isEmpty)
        #expect(try persistence.loadConfiguration().photoMappings.isEmpty)
        #expect(store.statusMessage.contains("Could not save configuration"))
    }

    @Test("The permission fix is delivered as a file plus a paste-safe command")
    func permissionGrantScriptIsWrittenToDisk() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = try SystemSecurityDiagnostics.writePermissionGrantScript(to: directory)
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(contents.hasPrefix("#!/bin/bash"))

        let permissions = try FileManager.default
            .attributesOfItem(atPath: scriptURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.int16Value == 0o700)

        // The copied command is what the user pastes. An interactive zsh
        // expands "!" as a history event, so the command must not contain one.
        let command = SystemSecurityDiagnostics.permissionGrantCommand(forScriptAt: scriptURL)
        #expect(command.hasPrefix("bash '"))
        #expect(command.contains(scriptURL.path))
        #expect(!command.contains("!"))
        #expect(!command.contains("#"))
        #expect(!command.contains("\n"))
    }
}

private func propertyList(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
}

private func shellOutput(_ command: String) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let value = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw SecurityHardeningTestError.shellFailed(process.terminationStatus, value)
    }
    return value
}

private enum SecurityHardeningTestError: Error {
    case shellFailed(Int32, String)
}

private struct PreciseDatePayload: Codable {
    let date: Date
}
