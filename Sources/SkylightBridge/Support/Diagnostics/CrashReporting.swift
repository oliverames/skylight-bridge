import Foundation
import os.log
import Sentry

private let log = Logger(subsystem: "com.oliverames.SkylightBridge", category: "CrashReporting")

/// Crash and error reporting through Sentry.
///
/// A build without `SkylightSentryDSN` in its Info.plist never starts the SDK.
/// Only release builds made by `script/build_release.sh` carry one; it is
/// written from 1Password at build time and is not in Git. The main window's
/// Sync > Privacy > Share crash reports turns reporting off; it is on by default in
/// those builds. Debug builds report only when launched with
/// `-SkylightCrashReports YES` or `-SkylightSentryTest message|error|crash`.
///
/// What is sent is an allowlist enforced in `beforeSend`, not a text filter:
/// - Crash reports and uncaught exceptions: the exception type and mechanism,
///   and each thread's stack frames (function, image, code addresses, and a
///   path reduced to its place inside the app, a macOS system path, or a file
///   name). Exception messages, thread names, register values, source context,
///   frame variables, extra data, the request and the transaction are removed.
/// - Non-fatal sync and account failures built from fixed fields: the area, a
///   fixed message, and the error's domain and numeric code. At most one per
///   kind an hour and ten per run. Offline and cancelled requests are skipped.
/// - Breadcrumbs the app adds itself: fixed messages and counts.
/// - App version and build, macOS version, and the Mac's model and architecture.
///
/// Never sent: the Skylight account, tokens, frame, device, household member,
/// list, chore, recipe, note, meal, photo or album names and identifiers,
/// calendar data, file names, the IP address (no `sendDefaultPii`, and the
/// project discards IP addresses), sessions, performance traces, network
/// requests, screenshots or user interface details.
enum CrashReporting {
    static let preferenceKey = "SkylightShareCrashReports"
    private static let dsnKey = "SkylightSentryDSN"
    static let ownEventFingerprintHead = "skylight-report"

    /// The validated DSN this build carries, or nil when reporting isn't built in.
    static let dsn: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: dsnKey) as? String,
              !value.isEmpty,
              let url = URLComponents(string: value), url.scheme == "https",
              url.host?.hasSuffix(".sentry.io") == true, url.user?.isEmpty == false,
              url.password == nil, url.query == nil else { return nil }
        return value
    }()

    static var isConfigured: Bool { dsn != nil }

    /// On unless the person turned it off.
    static var isPreferenceOn: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    static var isRunning: Bool { SentrySDK.isEnabled }

    @MainActor private static var rateLimiter = DiagnosticsRateLimiter()

    /// Starts reporting when the build has a DSN and the person hasn't turned
    /// it off. Call first thing at launch, on the main thread.
    @MainActor
    static func start() {
        guard let dsn, isPreferenceOn, !SentrySDK.isEnabled else { return }
        #if DEBUG
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "SkylightCrashReports") || defaults.string(forKey: "SkylightSentryTest") != nil else {
            return
        }
        #endif
        SentrySDK.start(options: options(dsn: dsn))
        log.info("Crash reporting started")
    }

    /// Share crash reports. Takes effect at once: off closes the SDK and its
    /// crash handler, on starts it again.
    @MainActor
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled { start() } else if SentrySDK.isEnabled { SentrySDK.close() }
    }

    // MARK: Breadcrumbs and reports

    /// A step leading up to a possible crash. The message is a fixed phrase;
    /// data holds counts only.
    @MainActor
    static func breadcrumb(_ area: DiagnosticsArea, _ message: StaticString, counts: [String: Int] = [:]) {
        guard SentrySDK.isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: area.rawValue)
        crumb.message = "\(message)"
        for (key, value) in counts { crumb.setData(value: value, key: key) }
        SentrySDK.addBreadcrumb(crumb)
    }

    /// A non-fatal failure worth fixing. Only the error's domain and numeric
    /// code go with it: its description can name a list, a photo or an account.
    @MainActor
    static func report(_ area: DiagnosticsArea, _ message: StaticString, error: any Error) {
        guard SentrySDK.isEnabled, !DiagnosticsPrivacy.isExpectedNetworkCondition(error) else { return }
        let nsError = error as NSError
        let text = "\(message)"
        let key = [area.rawValue, text, nsError.domain, String(nsError.code)].joined(separator: "|")
        guard rateLimiter.shouldSend(key: key, now: Date().timeIntervalSince1970) else { return }
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: text)
        event.tags = [
            "area": area.rawValue,
            "error_domain": nsError.domain,
            "error_code": String(nsError.code),
        ]
        event.fingerprint = [ownEventFingerprintHead, area.rawValue, text, nsError.domain, String(nsError.code)]
        SentrySDK.capture(event: event)
    }

    // MARK: Options

    private static func options(dsn: String) -> Options {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let options = Options()
        options.dsn = dsn
        // Matches script/build_release.sh, so uploaded dSYMs attach to the release.
        options.releaseName = "com.oliverames.SkylightBridge@\(version)+\(build)"
        options.dist = build
        #if DEBUG
        options.environment = "debug"
        #else
        options.environment = "production"
        #endif
        options.debug = false
        options.sendDefaultPii = false
        options.enableCrashHandler = true
        options.enableUncaughtNSExceptionReporting = true
        // No sessions (they carry an installation identifier), tracing,
        // network capture, automatic breadcrumbs, hangs or MetricKit.
        options.enableAutoSessionTracking = false
        options.tracesSampleRate = 0
        options.enableAutoPerformanceTracing = false
        options.enableNetworkTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableAutoBreadcrumbTracking = false
        options.enableSwizzling = false
        options.enableAppHangTracking = false
        options.enableMetricKit = false
        options.enableLogs = false
        options.attachStacktrace = false
        options.maxAttachmentSize = 0
        options.tracePropagationTargets = []
        options.failedRequestTargets = []
        // Counts of dropped reports and why, with no contents.
        options.sendClientReports = true
        options.beforeBreadcrumb = { crumb in
            filter(crumb)
        }
        options.beforeSend = { event in
            guard isPreferenceOn else { return nil }
            return scrub(event)
        }
        return options
    }

    /// Keep only the app's own breadcrumbs, with counts and a cleaned message.
    static func filter(_ crumb: Breadcrumb) -> Breadcrumb? {
        guard DiagnosticsPrivacy.isAllowedBreadcrumb(category: crumb.category) else { return nil }
        crumb.message = crumb.message.map { DiagnosticsPrivacy.scrub($0) }
        let data = crumb.data ?? [:]
        let numbers = DiagnosticsPrivacy.filterBreadcrumbData(data)
        for key in data.keys where numbers[key] == nil { crumb.setData(value: nil, key: key) }
        return crumb
    }

    /// The running app's bundle, used to reduce frame and image paths.
    static let bundlePath = Bundle.main.bundlePath

    /// Allowlist every event before it leaves the Mac, including crash reports
    /// written by an earlier run. Free-text fields the SDK fills are removed,
    /// not filtered.
    static func scrub(_ event: Event) -> Event {
        event.serverName = nil
        event.user = nil
        event.extra = nil
        event.transaction = nil
        event.modules = nil
        event.request = nil
        event.stacktrace = nil
        event.context = event.context.flatMap {
            let kept = DiagnosticsPrivacy.filterContexts($0)
            return kept.isEmpty ? nil : kept
        }
        if event.fingerprint?.first == ownEventFingerprintHead {
            event.message = event.message.map { SentryMessage(formatted: DiagnosticsPrivacy.scrub($0.formatted)) }
            event.tags = event.tags.map(DiagnosticsPrivacy.filterTags)
            // Fingerprints are sent too; they hold the error domain and code.
            event.fingerprint = event.fingerprint?.map { DiagnosticsPrivacy.scrub($0) }
        } else {
            event.message = nil
            event.tags = nil
            event.fingerprint = nil
        }
        for exception in event.exceptions ?? [] {
            exception.value = nil
            exception.type = exception.type.map { DiagnosticsPrivacy.scrub($0) }
            if let mechanism = exception.mechanism {
                mechanism.desc = nil
                mechanism.data = nil
                mechanism.helpLink = nil
                mechanism.type = DiagnosticsPrivacy.scrub(mechanism.type)
            }
            reduceFrames(exception.stacktrace)
        }
        for thread in event.threads ?? [] {
            thread.name = nil
            reduceFrames(thread.stacktrace)
        }
        for image in event.debugMeta ?? [] {
            image.codeFile = image.codeFile.map { DiagnosticsPrivacy.reducePath($0, bundlePath: bundlePath) }
        }
        event.breadcrumbs = event.breadcrumbs?.compactMap(filter)
        return event
    }

    /// Keep function names, images and code addresses; reduce paths; drop
    /// register values (they can hold short strings), source context and variables.
    private static func reduceFrames(_ stacktrace: SentryStacktrace?) {
        stacktrace?.registers = [:]
        for frame in stacktrace?.frames ?? [] {
            frame.package = frame.package.map { DiagnosticsPrivacy.reducePath($0, bundlePath: bundlePath) }
            frame.fileName = frame.fileName.map { DiagnosticsPrivacy.reducePath($0, bundlePath: bundlePath) }
            frame.contextLine = nil
            frame.preContext = nil
            frame.postContext = nil
            frame.vars = nil
        }
    }

    // MARK: Debug checks

    #if DEBUG
    /// Handles `-SkylightSentryTest message|error|crash` and returns true when
    /// the process should exit without starting the app, so a delivery check
    /// never loads the configuration or touches Apple data. The breadcrumb and
    /// error carry synthetic private text, so the received event shows whether
    /// scrubbing worked: none of it should arrive. `message` also uploads a
    /// crash report left by an earlier `crash` run.
    @MainActor
    static func runDebugTestIfRequested() -> Bool {
        guard let kind = UserDefaults.standard.string(forKey: "SkylightSentryTest") else { return false }
        guard SentrySDK.isEnabled else {
            log.notice("Sentry test skipped: no DSN in this build, or reporting is off")
            return true
        }
        let crumb = Breadcrumb(level: .info, category: DiagnosticsArea.test.rawValue)
        crumb.message = "Scrub check for \"Smith Family Frame\" in /Users/jane/Pictures/Beach.heic jane@example.com https://app.ourskylight.com/frames/1234567"
        crumb.setData(value: 3, key: "count")
        crumb.setData(value: "Groceries", key: "listName")
        crumb.setData(value: "Jane Smith", key: "member")
        SentrySDK.addBreadcrumb(crumb)
        switch kind {
        case "crash":
            SentrySDK.crash()
        case "error":
            let error = NSError(domain: "SkylightBridge.DiagnosticsCheck", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Could not sync list \"Groceries\" for jane@example.com",
            ])
            report(.test, "Skylight Bridge diagnostics check (error)", error: error)
        default:
            let event = Event(level: .info)
            event.message = SentryMessage(formatted: "Skylight Bridge diagnostics check")
            event.fingerprint = [ownEventFingerprintHead, "delivery-test"]
            event.tags = ["area": DiagnosticsArea.test.rawValue, "delivery_test": "true"]
            let eventID = SentrySDK.capture(event: event)
            log.notice("Sentry test event: \(eventID.sentryIdString, privacy: .public)")
            print("Sentry test event: \(eventID.sentryIdString)")
        }
        SentrySDK.flush(timeout: 10)
        return true
    }
    #endif
}
