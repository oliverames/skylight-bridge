import CryptoKit
import Foundation
import Security

// Standalone fixtures. Compile only this file and LocalFileAuthenticator.swift.
// No account-based initializer, real Keychain backend, app target, or file store runs.
@main
enum LocalFileAuthenticatorFixtureTests {
    private static let signingKey = Data(repeating: 0x2A, count: 32)
    private static let value = FixtureValue(
        message: "Synthetic integrity fixture",
        timestamp: Date(timeIntervalSince1970: 1_759_766_400.123456)
    )

    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("validExistingKeyNeverWrites", validExistingKeyNeverWrites),
            ("missingKeyNeverWrites", missingKeyNeverWrites),
            ("deniedKeysNeverWrite", deniedKeysNeverWrite),
            ("wrongKeyNeverWrites", wrongKeyNeverWrites),
            ("malformedEnvelopeNeverConsultsKeys", malformedEnvelopeNeverConsultsKeys),
            ("unsupportedVersionNeverConsultsKeys", unsupportedVersionNeverConsultsKeys),
            ("tamperedPayloadIsRejected", tamperedPayloadIsRejected),
            ("tamperedTagIsRejected", tamperedTagIsRejected),
            ("freshSealCreatesOnceAndReusesKey", freshSealCreatesOnceAndReusesKey),
            ("testKeyInitializerRoundTrips", testKeyInitializerRoundTrips),
            ("timestampPrecisionIsPreserved", timestampPrecisionIsPreserved),
            ("legacyISO8601TimestampsStillOpen", legacyISO8601TimestampsStillOpen),
            ("independentVersionOneEnvelopeStillOpens", independentVersionOneEnvelopeStillOpens)
        ]
        var completed = 0
        for (name, test) in tests {
            try test()
            completed += 1
            print("PASS \(name)")
        }
        try require(completed == 13, "Every planned fixture must execute.")
        print("Executed \(completed) synthetic fixtures. No tests skipped.")
    }

    private static func sealedFixture() throws -> Data {
        try LocalFileAuthenticator(testKey: signingKey).seal(value)
    }

    private static func validExistingKeyNeverWrites() throws {
        let provider = MemoryKeyProvider(key: signingKey)
        let actual = try provider.authenticator.open(FixtureValue.self, from: sealedFixture())
        try require(actual == value, "Existing key must recover the original payload.")
        try require(provider.counts == Counts(reads: 1, writes: 0, creations: 0), "Read created or requested a key.")
    }

    private static func missingKeyNeverWrites() throws {
        let provider = MemoryKeyProvider(key: nil)
        let input = try sealedFixture()
        try expectError({ _ = try provider.authenticator.open(FixtureValue.self, from: input) }) {
            if case LocalFileIntegrityError.missingIntegrityKey = $0 { return true }
            return false
        }
        try require(provider.counts == Counts(reads: 1, writes: 0, creations: 0), "Missing-key read invoked creation.")
        try require(provider.currentKey == nil, "Missing-key read installed a replacement key.")
    }

    private static func deniedKeysNeverWrite() throws {
        for status in [errSecInteractionNotAllowed, errSecAuthFailed] {
            let provider = MemoryKeyProvider(key: signingKey, readFailure: status)
            let input = try sealedFixture()
            try expectError({ _ = try provider.authenticator.open(FixtureValue.self, from: input) }) {
                if case let LocalFileIntegrityError.keychainFailure(actual) = $0 { return actual == status }
                return false
            }
            try require(provider.counts == Counts(reads: 1, writes: 0, creations: 0), "Denied read invoked creation.")
            try require(provider.currentKey == signingKey, "Denied read changed the stored fixture key.")
        }
    }

    private static func wrongKeyNeverWrites() throws {
        let provider = MemoryKeyProvider(key: Data(repeating: 0xBB, count: 32))
        let input = try sealedFixture()
        try expectIntegrityFailure { _ = try provider.authenticator.open(FixtureValue.self, from: input) }
        try require(provider.counts == Counts(reads: 1, writes: 0, creations: 0), "Wrong-key read invoked creation.")
    }

    private static func malformedEnvelopeNeverConsultsKeys() throws {
        let provider = MemoryKeyProvider(key: nil)
        try expectInvalidEnvelope {
            _ = try provider.authenticator.open(FixtureValue.self, from: Data("not JSON".utf8))
        }
        try require(provider.counts == Counts(reads: 0, writes: 0, creations: 0), "Malformed input consulted key providers.")
    }

    private static func unsupportedVersionNeverConsultsKeys() throws {
        let provider = MemoryKeyProvider(key: nil)
        var envelope = try JSONDecoder().decode(FixtureEnvelope.self, from: sealedFixture())
        envelope.version = 2
        let input = try JSONEncoder().encode(envelope)
        try expectInvalidEnvelope { _ = try provider.authenticator.open(FixtureValue.self, from: input) }
        try require(provider.counts == Counts(reads: 0, writes: 0, creations: 0), "Unsupported version consulted key providers.")
    }

    private static func tamperedPayloadIsRejected() throws {
        let provider = MemoryKeyProvider(key: signingKey)
        var envelope = try JSONDecoder().decode(FixtureEnvelope.self, from: sealedFixture())
        envelope.payload[envelope.payload.startIndex] ^= 1
        let input = try JSONEncoder().encode(envelope)
        try expectIntegrityFailure { _ = try provider.authenticator.open(FixtureValue.self, from: input) }
        try require(provider.counts == Counts(reads: 1, writes: 0, creations: 0), "Tampered payload invoked creation.")
    }

    private static func tamperedTagIsRejected() throws {
        let provider = MemoryKeyProvider(key: signingKey)
        var envelope = try JSONDecoder().decode(FixtureEnvelope.self, from: sealedFixture())
        envelope.authenticationTag[envelope.authenticationTag.startIndex] ^= 1
        let input = try JSONEncoder().encode(envelope)
        try expectIntegrityFailure { _ = try provider.authenticator.open(FixtureValue.self, from: input) }
        try require(provider.counts == Counts(reads: 1, writes: 0, creations: 0), "Tampered tag invoked creation.")
    }

    private static func freshSealCreatesOnceAndReusesKey() throws {
        let provider = MemoryKeyProvider(key: nil)
        let authenticator = provider.authenticator
        let first = try authenticator.seal(value)
        let second = try authenticator.seal(value)
        try require(provider.counts == Counts(reads: 0, writes: 2, creations: 1), "First write must create once, then reuse.")
        try require(provider.currentKey?.count == 32, "Synthetic first-write key must have the existing size.")
        let actualFirst = try authenticator.open(FixtureValue.self, from: first)
        let actualSecond = try authenticator.open(FixtureValue.self, from: second)
        try require(actualFirst == value && actualSecond == value, "Fresh seals must remain readable.")
        try require(provider.counts == Counts(reads: 2, writes: 2, creations: 1), "Opening fresh seals must not write keys.")
    }

    private static func testKeyInitializerRoundTrips() throws {
        let authenticator = LocalFileAuthenticator(testKey: signingKey)
        let actual = try authenticator.open(FixtureValue.self, from: authenticator.seal(value))
        try require(actual == value, "Existing test-key initializer changed behavior.")
    }

    private static func timestampPrecisionIsPreserved() throws {
        let authenticator = LocalFileAuthenticator(testKey: signingKey)
        let input = try authenticator.seal(value)
        let envelope = try JSONDecoder().decode(FixtureEnvelope.self, from: input)
        let payload = try JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any]
        try require(envelope.version == 1, "Envelope version changed.")
        try require(payload?["timestamp"] is NSNumber, "New dates must remain numeric timestamps.")
        let actual = try authenticator.open(FixtureValue.self, from: input)
        try require(actual.timestamp == value.timestamp, "Timestamp precision changed.")
    }

    private static func legacyISO8601TimestampsStillOpen() throws {
        for text in ["2026-10-06T12:00:00Z", "2026-10-06T12:00:00.125Z"] {
            let payload = try JSONSerialization.data(withJSONObject: ["message": "Legacy fixture", "timestamp": text], options: [.sortedKeys])
            let input = try makeEnvelope(payload: payload)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = text.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            guard let expected = formatter.date(from: text) else { throw FixtureFailure("Invalid synthetic legacy date.") }
            let actual = try LocalFileAuthenticator(testKey: signingKey).open(FixtureValue.self, from: input)
            try require(actual.timestamp == expected, "Legacy ISO 8601 timestamp was not preserved.")
        }
    }

    private static func independentVersionOneEnvelopeStillOpens() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let input = try makeEnvelope(payload: encoder.encode(value))
        let provider = MemoryKeyProvider(key: signingKey)
        let actual = try provider.authenticator.open(FixtureValue.self, from: input)
        try require(actual == value, "Existing version-one encoding no longer opens.")
        try require(provider.counts == Counts(reads: 1, writes: 0, creations: 0), "Compatibility read invoked creation.")
    }

    private static func makeEnvelope(payload: Data) throws -> Data {
        let tag = Data(HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: signingKey)))
        return try JSONEncoder().encode(FixtureEnvelope(version: 1, payload: payload, authenticationTag: tag))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw FixtureFailure(message) }
    }

    private static func expectError(_ operation: () throws -> Void, matching predicate: (Error) -> Bool) throws {
        do {
            try operation()
        } catch {
            try require(predicate(error), "Unexpected error: \(error)")
            return
        }
        throw FixtureFailure("Expected an error, but operation succeeded.")
    }

    private static func expectIntegrityFailure(_ operation: () throws -> Void) throws {
        try expectError(operation) {
            if case LocalFileIntegrityError.integrityCheckFailed = $0 { return true }
            return false
        }
    }

    private static func expectInvalidEnvelope(_ operation: () throws -> Void) throws {
        try expectError(operation) {
            if case LocalFileIntegrityError.invalidEnvelope = $0 { return true }
            return false
        }
    }
}

private struct FixtureValue: Codable, Equatable, Sendable {
    let message: String
    let timestamp: Date
}

private struct FixtureEnvelope: Codable {
    var version: Int
    var payload: Data
    var authenticationTag: Data
}

private struct FixtureFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct Counts: Equatable {
    let reads: Int
    let writes: Int
    let creations: Int
}

// Every mutable property is accessed under this lock. Providers remain synchronous.
private final class MemoryKeyProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?
    private let readFailure: OSStatus?
    private var readCount = 0
    private var writeCount = 0
    private var creationCount = 0

    init(key: Data?, readFailure: OSStatus? = nil) {
        self.key = key
        self.readFailure = readFailure
    }

    var authenticator: LocalFileAuthenticator {
        LocalFileAuthenticator(
            existingKeyProvider: { try self.readExisting() },
            writeKeyProvider: { self.keyForWriting() }
        )
    }

    var currentKey: Data? { lock.withLock { key } }

    var counts: Counts {
        lock.withLock { Counts(reads: readCount, writes: writeCount, creations: creationCount) }
    }

    private func readExisting() throws -> Data? {
        try lock.withLock {
            readCount += 1
            if let readFailure { throw LocalFileIntegrityError.keychainFailure(readFailure) }
            return key
        }
    }

    private func keyForWriting() -> Data {
        lock.withLock {
            writeCount += 1
            if let key { return key }
            let created = Data(repeating: 0x4C, count: 32)
            key = created
            creationCount += 1
            return created
        }
    }
}
