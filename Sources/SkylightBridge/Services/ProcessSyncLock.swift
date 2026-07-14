import Darwin
import Foundation

enum ProcessSyncLockError: Error, LocalizedError, Sendable {
    case anotherSyncIsRunning
    case couldNotCreateLock

    var errorDescription: String? {
        switch self {
        case .anotherSyncIsRunning:
            "Another Skylight Bridge process is already synchronizing."
        case .couldNotCreateLock:
            "Skylight Bridge could not create its synchronization lock."
        }
    }
}

final class ProcessSyncLock: @unchecked Sendable {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    static func acquire(fileManager: FileManager = .default) throws -> ProcessSyncLock {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkylightBridge", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

        let descriptor = open(
            root.appendingPathComponent("sync.lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw ProcessSyncLockError.couldNotCreateLock
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            if errno == EWOULDBLOCK {
                throw ProcessSyncLockError.anotherSyncIsRunning
            }
            throw ProcessSyncLockError.couldNotCreateLock
        }
        return ProcessSyncLock(fileDescriptor: descriptor)
    }
}
