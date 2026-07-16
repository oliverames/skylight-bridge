import Foundation
import Testing
@testable import SkylightBridge

struct SharedCloudKitFailureTests {
    @Test("Production schema errors are identified without exposing CloudKit internals")
    func identifiesProductionSchemaConfigurationError() {
        let error = NSError(
            domain: "CKErrorDomain",
            code: 15,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot create new type SharedPreferences in production schema"
            ]
        )

        #expect(SharedCloudKitFailure.isProductionSchemaConfigurationError(error))
        #expect(
            SharedCloudKitFailure.activityMessage(for: error, savedLocally: true) ==
                "Saved on this Mac. iCloud sharing needs its schema deployed to production before it can sync."
        )
    }

    @Test("Temporary iCloud failures retain their original message")
    func preservesTemporaryErrorMessage() {
        let error = NSError(
            domain: "CKErrorDomain",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "The network is unavailable."]
        )

        #expect(!SharedCloudKitFailure.isProductionSchemaConfigurationError(error))
        #expect(
            SharedCloudKitFailure.activityMessage(for: error, savedLocally: false) ==
                "iCloud sharing is unavailable: The network is unavailable."
        )
    }
}
