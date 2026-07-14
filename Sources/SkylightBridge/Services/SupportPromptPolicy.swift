import Foundation

/// Decides when the donation prompt may appear. Modeled on Ping Warden's
/// policy: the app must have demonstrated value first (synchronized changes
/// crossing a milestone), prompts respect long cooldowns, and a permanent
/// dismissal is forever. Pure logic so it is directly testable.
enum SupportPromptPolicy {
    /// Lifetime applied-change counts that each unlock one reminder.
    static let milestones = [50, 500, 2_000, 10_000]
    /// Minimum time between prompts even when a new milestone is crossed.
    static let promptCooldown: TimeInterval = 30 * 24 * 60 * 60
    /// Grace period after the user actually opened the donation page.
    static let supportCooldown: TimeInterval = 180 * 24 * 60 * 60

    struct Context: Sendable {
        var isConnected: Bool
        var isSyncing: Bool
        var lifetimeAppliedChanges: Int
        /// Highest milestone already prompted for (0 = never prompted).
        var promptedMilestone: Int
        var dismissedPermanently: Bool
        var lastPromptDate: Date?
        var supportOpenedDate: Date?
        var now: Date
    }

    /// The milestone to thank the user for now, or nil when no prompt is due.
    static func milestoneToPrompt(_ context: Context) -> Int? {
        guard context.isConnected,
              !context.isSyncing,
              !context.dismissedPermanently else {
            return nil
        }
        guard let milestone = milestones.last(where: {
            $0 <= context.lifetimeAppliedChanges && $0 > context.promptedMilestone
        }) else {
            return nil
        }
        if let lastPromptDate = context.lastPromptDate,
           context.now.timeIntervalSince(lastPromptDate) < promptCooldown {
            return nil
        }
        if let supportOpenedDate = context.supportOpenedDate,
           context.now.timeIntervalSince(supportOpenedDate) < supportCooldown {
            return nil
        }
        return milestone
    }
}
