import Foundation

actor SyncStateStore {
    private static let maximumStateBytes = 4_194_304

    private let fileManager: FileManager
    private let fileURL: URL
    private let authenticator: LocalFileAuthenticator

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        authenticator: LocalFileAuthenticator = LocalFileAuthenticator(
            account: "sync-state-signing-key"
        )
    ) {
        self.fileManager = fileManager
        self.authenticator = authenticator
        let root = rootURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("SkylightBridge", isDirectory: true)
        fileURL = root.appendingPathComponent("sync-state.json")
    }

    func load() throws -> SyncState {
        guard fileManager.fileExists(atPath: fileURL.path) else { return SyncState() }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maximumStateBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        return try authenticator.open(
            SyncState.self,
            from: Data(contentsOf: fileURL, options: .mappedIfSafe)
        )
    }

    func save(_ state: SyncState) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fileURL.deletingLastPathComponent().path
        )
        try authenticator.seal(state).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
