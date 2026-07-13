import Foundation

struct ConfigurationStore {
    private let fileManager: FileManager
    private let configurationURL: URL
    private let activityURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkylightBridge", isDirectory: true)
        configurationURL = root.appendingPathComponent("configuration.json")
        activityURL = root.appendingPathComponent("activity.json")
    }

    func loadConfiguration() throws -> AppConfiguration {
        guard fileManager.fileExists(atPath: configurationURL.path) else {
            return .empty
        }

        return try JSONDecoder.bridge.decode(
            AppConfiguration.self,
            from: Data(contentsOf: configurationURL)
        )
    }

    func saveConfiguration(_ configuration: AppConfiguration) throws {
        try prepareDirectory(for: configurationURL)
        try JSONEncoder.bridge.encode(configuration).write(to: configurationURL, options: .atomic)
    }

    func loadActivity() throws -> [ActivityEntry] {
        guard fileManager.fileExists(atPath: activityURL.path) else { return [] }
        return try JSONDecoder.bridge.decode([ActivityEntry].self, from: Data(contentsOf: activityURL))
    }

    func saveActivity(_ activity: [ActivityEntry]) throws {
        try prepareDirectory(for: activityURL)
        try JSONEncoder.bridge.encode(Array(activity.prefix(500))).write(to: activityURL, options: .atomic)
    }

    private func prepareDirectory(for fileURL: URL) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

private extension JSONEncoder {
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var bridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
