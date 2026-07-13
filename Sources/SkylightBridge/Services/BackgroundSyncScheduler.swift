import Foundation
import ServiceManagement

@MainActor
final class BackgroundSyncScheduler {
    private var scheduler: NSBackgroundActivityScheduler?

    func schedule(
        everyMinutes minutes: Int,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        cancel()

        let interval = TimeInterval(minutes) * 60
        let scheduler = NSBackgroundActivityScheduler(
            identifier: "com.oliverames.SkylightBridge.sync"
        )
        scheduler.interval = interval
        scheduler.tolerance = interval * 0.2
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                await operation()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    func cancel() {
        scheduler?.invalidate()
        scheduler = nil
    }
}

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
