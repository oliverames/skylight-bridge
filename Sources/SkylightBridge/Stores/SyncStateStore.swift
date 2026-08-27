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
        let sealed = try authenticator.seal(state)
        guard sealed.count <= Self.maximumStateBytes else {
            throw LocalPersistenceError.fileTooLarge(
                label: "sync state",
                maximumBytes: Self.maximumStateBytes
            )
        }
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fileURL.deletingLastPathComponent().path
        )
        try sealed.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Removes only local identity links for a reminder mapping. This supports
    /// “Remove Mapping Only” while signed out or offline because no Skylight or
    /// Apple Reminders operation is required.
    func removeReminderMappingRecords(mappingID: UUID) throws {
        var state = try load()
        state.reminders.removeAll { $0.mappingID == mappingID }
        state.reminderLists.removeAll { $0.mappingID == mappingID }
        try save(state)
    }
}
