import Foundation
import Testing
@testable import SkylightBridge

struct SupportPromptPolicyTests {
    private func context(
        lifetime: Int,
        prompted: Int = 0,
        dismissed: Bool = false,
        lastPrompt: Date? = nil,
        supportOpened: Date? = nil,
        connected: Bool = true,
        syncing: Bool = false,
        now: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> SupportPromptPolicy.Context {
        SupportPromptPolicy.Context(
            isConnected: connected,
            isSyncing: syncing,
            lifetimeAppliedChanges: lifetime,
            promptedMilestone: prompted,
            dismissedPermanently: dismissed,
            lastPromptDate: lastPrompt,
            supportOpenedDate: supportOpened,
            now: now
        )
    }

    @Test("No prompt before the first milestone")
    func noPromptBeforeFirstMilestone() {
        #expect(SupportPromptPolicy.milestoneToPrompt(context(lifetime: 49)) == nil)
    }

    @Test("First milestone prompts once, then stays quiet until the next")
    func firstMilestonePromptsOnce() {
        #expect(SupportPromptPolicy.milestoneToPrompt(context(lifetime: 50)) == 50)
        #expect(SupportPromptPolicy.milestoneToPrompt(context(lifetime: 499, prompted: 50)) == nil)
        let now = Date(timeIntervalSince1970: 100_000_000)
        let old = now.addingTimeInterval(-90 * 24 * 60 * 60)
        #expect(SupportPromptPolicy.milestoneToPrompt(
            context(lifetime: 500, prompted: 50, lastPrompt: old, now: now)
        ) == 500)
    }

    @Test("Skipping milestones prompts only for the highest one crossed")
    func skipsToHighestMilestone() {
        #expect(SupportPromptPolicy.milestoneToPrompt(context(lifetime: 2_500)) == 2_000)
    }

    @Test("Prompt cooldown suppresses a freshly crossed milestone")
    func promptCooldownSuppresses() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-24 * 60 * 60)
        #expect(SupportPromptPolicy.milestoneToPrompt(
            context(lifetime: 500, prompted: 50, lastPrompt: recent, now: now)
        ) == nil)
    }

    @Test("A recent donation suppresses prompts for six months")
    func supportCooldownSuppresses() {
        let now = Date(timeIntervalSince1970: 100_000_000)
        let recentSupport = now.addingTimeInterval(-30 * 24 * 60 * 60)
        #expect(SupportPromptPolicy.milestoneToPrompt(
            context(lifetime: 10_000, supportOpened: recentSupport, now: now)
        ) == nil)
    }

    @Test("Permanent dismissal and disconnected states never prompt")
    func hardBlocksNeverPrompt() {
        #expect(SupportPromptPolicy.milestoneToPrompt(context(lifetime: 10_000, dismissed: true)) == nil)
        #expect(SupportPromptPolicy.milestoneToPrompt(context(lifetime: 10_000, connected: false)) == nil)
        #expect(SupportPromptPolicy.milestoneToPrompt(context(lifetime: 10_000, syncing: true)) == nil)
    }
}
