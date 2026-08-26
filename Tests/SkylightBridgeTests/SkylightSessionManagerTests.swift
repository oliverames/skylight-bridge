import Foundation
import Testing
@testable import SkylightBridge

struct SkylightSessionManagerTests {
    @Test("Sign-out deletes every account secret and keeps the install fingerprint")
    func signOutDeletesAllSecrets() async throws {
        let store = CredentialStoreStub()
        await store.seed(
            email: "person@example.com",
            password: "secret",
            accessToken: "access-token",
            refreshToken: "refresh-token"
            // No fingerprint seeded: the revoke path stays off, so the test
            // never touches the network.
        )
        let manager = SkylightSessionManager(credentials: store)

        try await manager.signOut()

        let state = await store.state
        #expect(state["email"] == nil)
        #expect(state["password"] == nil)
        #expect(state["oauth-access-token"] == nil)
        #expect(state["oauth-refresh-token"] == nil)
        #expect(await store.deletedAccounts.sorted() == [
            "email", "oauth-access-token", "oauth-refresh-token", "password"
        ])
    }

    @Test("A Keychain error during sign-out still deletes the remaining secrets")
    func signOutContinuesPastOneFailure() async throws {
        let store = CredentialStoreStub()
        await store.seed(
            email: "person@example.com",
            password: "secret",
            accessToken: "access-token",
            refreshToken: "refresh-token"
        )
        await store.failDeletion(for: "password")
        let manager = SkylightSessionManager(credentials: store)

        do {
            try await manager.signOut()
            Issue.record("Expected sign-out to surface the Keychain failure")
        } catch {
            // Expected.
        }

        let deleted = await store.deletedAccounts
        let state = await store.state
        // Every secret was attempted despite the middle one failing, and the
        // failed one stays present for a retry.
        #expect(deleted == ["email", "oauth-access-token", "oauth-refresh-token"])
        #expect(state["password"] == "secret")
    }
}

private actor CredentialStoreStub: CredentialStoring {
    private(set) var state: [String: String] = [:]
    private(set) var deletedAccounts: [String] = []
    private var failingAccounts: Set<String> = []

    func seed(
        email: String,
        password: String,
        accessToken: String?,
        refreshToken: String?,
        deviceFingerprint: String = ""
    ) {
        if !email.isEmpty { state["email"] = email }
        if !password.isEmpty { state["password"] = password }
        if let accessToken { state["oauth-access-token"] = accessToken }
        if let refreshToken { state["oauth-refresh-token"] = refreshToken }
        if !deviceFingerprint.isEmpty { state["oauth-device-fingerprint"] = deviceFingerprint }
    }

    func failDeletion(for account: String) {
        failingAccounts.insert(account)
    }

    func save(_ value: String, for account: String) {
        state[account] = value
    }

    func string(for account: String) -> String? {
        state[account]
    }

    func delete(for account: String) throws {
        if failingAccounts.contains(account) {
            throw KeychainCredentialStoreError.operationFailed(
                status: errSecInteractionNotAllowed,
                message: "stubbed locked keychain"
            )
        }
        state.removeValue(forKey: account)
        deletedAccounts.append(account)
    }
}
