import Foundation

struct ConfigurationStore {
    private static let maximumConfigurationBytes = 1_048_576
    private static let maximumActivityBytes = 2_097_152

    private let fileManager: FileManager
    private let configurationURL: URL
    private let activityURL: URL
    private let configurationAuthenticator: LocalFileAuthenticator
    private let activityAuthenticator: LocalFileAuthenticator

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        configurationAuthenticator: LocalFileAuthenticator = LocalFileAuthenticator(
            account: "configuration-signing-key"
        ),
        activityAuthenticator: LocalFileAuthenticator = LocalFileAuthenticator(
            account: "activity-signing-key"
        )
    ) {
        self.fileManager = fileManager
        self.configurationAuthenticator = configurationAuthenticator
        self.activityAuthenticator = activityAuthenticator
        let root = rootURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("SkylightBridge", isDirectory: true)
        configurationURL = root.appendingPathComponent("configuration.json")
        activityURL = root.appendingPathComponent("activity.json")
    }

    func loadConfiguration() throws -> AppConfiguration {
        guard fileManager.fileExists(atPath: configurationURL.path) else {
            return .empty
        }

        return try configurationAuthenticator.open(
            AppConfiguration.self,
            from: try read(configurationURL, maximumBytes: Self.maximumConfigurationBytes)
        )
    }

    func saveConfiguration(_ configuration: AppConfiguration) throws {
        try prepareDirectory(for: configurationURL)
        try write(
            configurationAuthenticator.seal(configuration),
            to: configurationURL
        )
    }

    func loadActivity() throws -> [ActivityEntry] {
        guard fileManager.fileExists(atPath: activityURL.path) else { return [] }
        return try activityAuthenticator.open(
            [ActivityEntry].self,
            from: try read(activityURL, maximumBytes: Self.maximumActivityBytes)
        )
    }

    func saveActivity(_ activity: [ActivityEntry]) throws {
        try prepareDirectory(for: activityURL)
        try write(
            activityAuthenticator.seal(Array(activity.prefix(500))),
            to: activityURL
        )
    }

    private func prepareDirectory(for fileURL: URL) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fileURL.deletingLastPathComponent().path
        )
    }

    private func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
