import Foundation
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

/// Where a breadcrumb or report comes from. These are the only Sentry
/// categories Skylight Bridge sends.
enum DiagnosticsArea: String, Sendable, CaseIterable {
    case app, sync, account, test
}

/// The rules that decide what a crash or error report may carry. Nothing here
/// imports Sentry, so the rules are tested directly.
///
/// Skylight Bridge handles a household's private data: the Skylight account
/// email, password and tokens, frame and device names, household member
/// names, calendar events, Reminders lists and items, Apple Notes recipes and
/// meals, and photo names and albums. Reports are built from fixed messages,
/// enum values and numeric codes, so none of that is put into a report on
/// purpose. These rules are the second line of defence for text the SDK or
/// the system adds (exception reasons, thread names, file paths).
enum DiagnosticsPrivacy {
    static let bundleName = "Skylight Bridge.app"

    // MARK: Paths

    /// Read-only system locations. `/System/Volumes/` is excluded because the
    /// Data volume holds home folders.
    static let systemPrefixes = [
        "/System/Library/", "/System/iOSSupport/", "/System/Cryptexes/", "/usr/lib/", "/usr/libexec/",
    ]

    /// A frame or image path reduced to its place inside the app bundle, a
    /// macOS system path, or a bare file name. Home folders, build folders and
    /// volume names never leave the Mac.
    static func reducePath(_ path: String, bundlePath: String) -> String {
        let bundle = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        if !bundle.isEmpty, let range = path.range(of: bundle + "/", options: [.anchored, .caseInsensitive]) {
            return bundleName + "/" + path[range.upperBound...]
        }
        if !path.contains("/../"), systemPrefixes.contains(where: { path.hasPrefix($0) }) {
            return path
        }
        return (path as NSString).lastPathComponent
    }

    // MARK: Contexts

    /// SDK contexts that may be sent, and the keys kept in each: the app's
    /// version and build, the macOS version, and the Mac's model,
    /// architecture and memory and storage sizes. Every other context is
    /// dropped whole, including the "user info" context the SDK builds from an
    /// NSError's userInfo, which can hold file paths and names. Device names,
    /// locale, time zone and the app's start time are dropped too. App hang
    /// and watchdog tracking are off, so there are no keys of theirs to keep.
    static let allowedContextKeys: [String: Set<String>] = [
        "app": ["app_version", "app_build", "build_type"],
        "os": ["name", "version", "build", "kernel_version"],
        "device": ["family", "model", "arch", "memory_size", "storage_size"],
    ]

    /// Allowlisted keys only; strings are scrubbed and anything that is not a
    /// string, number or boolean is dropped.
    static func filterContexts(_ contexts: [String: [String: Any]]) -> [String: [String: Any]] {
        var kept: [String: [String: Any]] = [:]
        for (name, values) in contexts {
            guard let allowed = allowedContextKeys[name] else { continue }
            var filtered: [String: Any] = [:]
            for (key, value) in values where allowed.contains(key) {
                switch value {
                case let text as String: filtered[key] = scrub(text)
                case let number as NSNumber: filtered[key] = number
                default: break
                }
            }
            if !filtered.isEmpty { kept[name] = filtered }
        }
        return kept
    }

    // MARK: Tags and breadcrumbs

    /// Tags Skylight Bridge's own reports set. Everything else is removed.
    static let allowedTagKeys: Set<String> = ["area", "error_domain", "error_code", "delivery_test"]

    static func filterTags(_ tags: [String: String]) -> [String: String] {
        tags.filter { allowedTagKeys.contains($0.key) }.mapValues { scrub($0) }
    }

    static func isAllowedBreadcrumb(category: String) -> Bool {
        DiagnosticsArea(rawValue: category) != nil
    }

    /// Breadcrumb data keeps numbers and booleans only; any text value could
    /// be a name.
    static func filterBreadcrumbData(_ data: [String: Any]) -> [String: Any] {
        data.filter { $0.value is NSNumber }
    }

    // MARK: Text

    /// Longer text is cut; reports never need paragraphs.
    static let maximumLength = 200

    private static let rules: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            // Any URL, with its host, path and query. Skylight API paths carry
            // frame, list and photo identifiers.
            (#"[A-Za-z][A-Za-z0-9+.-]*://[^\s"'<>]+"#, "<url>"),
            (#"(?i)\b(authorization|cookie|api[_-]?key|token|access[_-]?token|refresh[_-]?token|password|secret|session(?:id)?|code)\b\s*[:=]\s*\S+"#, "$1=<redacted>"),
            (#"(?i)\bbearer\s+\S+"#, "Bearer <redacted>"),
            (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>"),
            // File system paths: home folders, containers, temporary files.
            (#"~?(?:/private)?/(?:var|Users|private|tmp|Library|Volumes|System/Volumes)/[^\s"']*"#, "<path>"),
            (#"~/[^\s"']*"#, "<path>"),
            // Quoted text is usually a name: a list, album, note, photo or person.
            (#""[^"\n]*""#, "\"<text>\""),
            (#"“[^”\n]*”"#, "“<text>”"),
            (#"'[^'\n]*'"#, "'<text>'"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#, "<ip>"),
            (#"\b(?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4}\b"#, "<ip>"),
            // Bare host names: dotted, all lowercase, ending in a letters-only label.
            (#"\b[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,12}\b(?::\d+)?"#, "<host>"),
            // Identifiers and opaque tokens: UUIDs, long hex, base64 and JWT-like runs.
            (#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#, "<id>"),
            (#"\b[A-Za-z0-9_-]{32,}\b"#, "<token>"),
            (#"\b[A-Fa-f0-9]{16,}\b"#, "<token>"),
            // Long digit runs: Skylight frame, list, chore and photo identifiers.
            (#"\b\d{5,}\b"#, "<number>"),
        ]
        return patterns.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    /// This Mac's account and computer names, which can appear in paths and
    /// in system-provided text.
    static let localIdentifiers: [String] = {
        var names = [NSUserName(), NSFullUserName()]
        #if canImport(SystemConfiguration)
        if let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? {
            names.append(computerName)
        }
        if let localHostName = SCDynamicStoreCopyLocalHostName(nil) as String? {
            names.append(localHostName)
        }
        #endif
        return names.filter { $0.count >= 3 }
    }()

    static func scrub(_ text: String, knownIdentifiers: [String] = localIdentifiers) -> String {
        var result = text
        for (expression, template) in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        for identifier in knownIdentifiers.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: identifier, with: "<local>", options: .caseInsensitive)
        }
        if result.count > maximumLength { result = String(result.prefix(maximumLength)) + "…" }
        return result
    }

    // MARK: Errors

    /// URL errors that only mean the Mac was offline or a request was
    /// cancelled. Background syncs would report them every interval.
    static func isExpectedNetworkCondition(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorCancelled, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
        ].contains(nsError.code)
    }
}

/// Limits non-fatal reports: one per kind an hour, and ten per app run, so a
/// failing background sync cannot flood the project. In memory only.
struct DiagnosticsRateLimiter: Sendable {
    static let interval: TimeInterval = 3_600
    static let maximumPerRun = 10

    private var lastSent: [String: TimeInterval] = [:]
    private var sentThisRun = 0

    mutating func shouldSend(key: String, now: TimeInterval) -> Bool {
        guard sentThisRun < Self.maximumPerRun else { return false }
        if let last = lastSent[key], now - last < Self.interval { return false }
        lastSent[key] = now
        sentThisRun += 1
        return true
    }
}
