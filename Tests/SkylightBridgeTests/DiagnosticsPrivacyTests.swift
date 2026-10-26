import Foundation
import Sentry
import Testing
@testable import SkylightBridge

struct DiagnosticsPrivacyTests {
    @Test func scrubRemovesHouseholdText() {
        let text = DiagnosticsPrivacy.scrub(
            "Could not sync \"Smith Family\" list 'Groceries' for jane@example.com at https://app.ourskylight.com/api/frames/1234567/lists?token=abc from /Users/jane/Pictures/Beach Day.heic and ~/Library/Caches/x",
            knownIdentifiers: ["janesmac"]
        )
        for secret in ["Smith", "Groceries", "jane", "ourskylight", "1234567", "abc", "Beach", "Caches"] {
            #expect(!text.contains(secret), "\(secret) leaked: \(text)")
        }
        #expect(text.hasPrefix("Could not sync"))
    }

    @Test func scrubRemovesTokensIdentifiersAndLocalNames() {
        let text = DiagnosticsPrivacy.scrub(
            "Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig refresh_token=r1 id 6F9619FF-8B86-D011-B42D-00C04FC964FF on Janes-MacBook-Pro from 192.168.1.20",
            knownIdentifiers: ["Janes-MacBook-Pro"]
        )
        for secret in ["eyJ", "r1", "6F9619FF", "Janes", "192.168"] {
            #expect(!text.contains(secret), "\(secret) leaked: \(text)")
        }
    }

    @Test func scrubKeepsTypeNamesAndCodes() {
        #expect(DiagnosticsPrivacy.scrub("SkylightBridge.SkylightAPIError code 3") == "SkylightBridge.SkylightAPIError code 3")
        #expect(DiagnosticsPrivacy.scrub("EXC_BAD_ACCESS") == "EXC_BAD_ACCESS")
    }

    @Test func pathsReduceToBundleSystemOrFileName() {
        let bundle = "/Applications/Skylight Bridge.app"
        #expect(DiagnosticsPrivacy.reducePath(bundle + "/Contents/MacOS/SkylightBridge", bundlePath: bundle)
            == "Skylight Bridge.app/Contents/MacOS/SkylightBridge")
        #expect(DiagnosticsPrivacy.reducePath("/System/Library/Frameworks/AppKit.framework/AppKit", bundlePath: bundle)
            == "/System/Library/Frameworks/AppKit.framework/AppKit")
        #expect(DiagnosticsPrivacy.reducePath("/Users/jane/Developer/skylight-bridge/Sources/App.swift", bundlePath: bundle)
            == "App.swift")
        #expect(DiagnosticsPrivacy.reducePath("/System/Library/../../Users/jane/x.dylib", bundlePath: bundle) == "x.dylib")
    }

    @Test func contextsKeepOnlyVersionsAndModel() {
        let kept = DiagnosticsPrivacy.filterContexts([
            "device": ["model": "Mac15,3", "name": "Jane's MacBook", "locale": "en_US", "arch": "arm64"],
            "culture": ["timezone": "America/New_York"],
            "app": ["app_version": "1.7.3", "device_app_hash": "abc", "app_start_time": "x"],
        ])
        let device = kept["device"].map { Array($0.keys).sorted() }
        let app = kept["app"].map { Array($0.keys).sorted() }
        #expect(device == ["arch", "model"])
        #expect(kept["culture"] == nil)
        #expect(app == ["app_version"])
    }

    @Test func contextsDropUserInfoAndFreeFormDictionaries() {
        let kept = DiagnosticsPrivacy.filterContexts([
            "user info": ["NSFilePath": "/Users/jane/Pictures/Beach.heic"],
            "SkylightCustom": ["list": "Groceries"],
            "os": ["name": "macOS", "version": "26.2", "rooted": false, "extra": "x"],
            "device": ["model": "Mac15,3", "memory_size": 34_359_738_368, "nested": ["name": "Jane"]],
        ])
        #expect(kept.keys.sorted() == ["device", "os"])
        let os = kept["os"].map { Array($0.keys).sorted() }
        let device = kept["device"].map { Array($0.keys).sorted() }
        #expect(os == ["name", "version"])
        #expect(device == ["memory_size", "model"])
    }

    @Test func rateLimiterAllowsOnePerHourAndTenPerRun() {
        var limiter = DiagnosticsRateLimiter()
        var results: [Bool] = []
        results.append(limiter.shouldSend(key: "a", now: 0))
        results.append(limiter.shouldSend(key: "a", now: 60))
        results.append(limiter.shouldSend(key: "a", now: 3_601))
        for index in 0..<8 { results.append(limiter.shouldSend(key: "k\(index)", now: 0)) }
        results.append(limiter.shouldSend(key: "another", now: 0))
        #expect(results == [true, false, true] + Array(repeating: true, count: 8) + [false])
    }

    @Test func offlineAndCancelledRequestsAreNotReported() {
        #expect(DiagnosticsPrivacy.isExpectedNetworkCondition(URLError(.notConnectedToInternet)))
        #expect(DiagnosticsPrivacy.isExpectedNetworkCondition(CancellationError()))
        #expect(!DiagnosticsPrivacy.isExpectedNetworkCondition(URLError(.badServerResponse)))
    }

    @Test func eventScrubRemovesFreeTextFromCrashReports() {
        let event = Event(level: .fatal)
        event.message = SentryMessage(formatted: "Photo Beach.heic failed")
        event.tags = ["list": "Groceries"]
        event.extra = ["email": "jane@example.com"]
        event.user = User(userId: "jane")
        event.serverName = "Janes-MacBook-Pro"
        event.context = ["device": ["name": "Jane's MacBook", "model": "Mac15,3"], "culture": ["locale": "en_US"]]
        let exception = Exception(value: "Could not open /Users/jane/Pictures/Beach.heic", type: "NSInvalidArgumentException")
        let frame = Frame()
        frame.fileName = "/Users/jane/Developer/skylight-bridge/Sources/AppStore.swift"
        frame.vars = ["title": "Groceries"]
        let stack = SentryStacktrace(frames: [frame], registers: ["x0": "0x6a616e65"])
        exception.stacktrace = stack
        event.exceptions = [exception]
        let thread = SentryThread(threadId: 1)
        thread.name = "Sync Groceries"
        event.threads = [thread]
        let crumb = Breadcrumb(level: .info, category: "ui.click")
        crumb.message = "Groceries"
        let own = Breadcrumb(level: .info, category: "sync")
        own.message = "Sync finished"
        own.setData(value: 2, key: "applied")
        own.setData(value: "Groceries", key: "list")
        event.breadcrumbs = [crumb, own]

        let scrubbed = CrashReporting.scrub(event)
        #expect(scrubbed.message == nil)
        #expect(scrubbed.tags == nil)
        #expect(scrubbed.extra == nil)
        #expect(scrubbed.user == nil)
        #expect(scrubbed.serverName == nil)
        let context = scrubbed.context ?? [:]
        #expect(context["culture"] == nil)
        #expect(context["device"]?["name"] == nil)
        #expect(context["device"]?["model"] as? String == "Mac15,3")
        #expect(scrubbed.exceptions?.first?.value == nil)
        #expect(scrubbed.exceptions?.first?.type == "NSInvalidArgumentException")
        #expect(scrubbed.exceptions?.first?.stacktrace?.frames.first?.fileName == "AppStore.swift")
        #expect(scrubbed.exceptions?.first?.stacktrace?.frames.first?.vars == nil)
        let registers = scrubbed.exceptions?.first?.stacktrace?.registers ?? ["x": "y"]
        #expect(registers.isEmpty)
        #expect(scrubbed.threads?.first?.name == nil)
        #expect(scrubbed.breadcrumbs?.count == 1)
        let crumbKeys = scrubbed.breadcrumbs?.first?.data.map { Array($0.keys).sorted() }
        #expect(crumbKeys == ["applied"])
    }

    @Test func ownReportsKeepTheirFixedMessageAndAllowedTags() {
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "Sync failed")
        event.fingerprint = [CrashReporting.ownEventFingerprintHead, "sync"]
        event.tags = ["area": "sync", "error_code": "3", "list": "Groceries"]
        let scrubbed = CrashReporting.scrub(event)
        #expect(scrubbed.message?.formatted == "Sync failed")
        #expect(scrubbed.tags == ["area": "sync", "error_code": "3"])
    }
}
