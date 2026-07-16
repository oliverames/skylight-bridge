import Testing
@testable import SkylightBridge

struct ReminderListMetadataPlannerTests {
    private let link = ReminderListMetadataLink(
        baselineAppleTitle: "Groceries",
        baselineSkylightTitle: "Groceries"
    )

    @Test("An Apple list rename updates its linked Skylight list")
    func appleRenameUpdatesSkylight() {
        let action = ReminderListMetadataPlanner.plan(
            appleTitle: "Weekend groceries",
            skylightTitle: "Groceries",
            link: link,
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(action == .updateRemote(title: "Weekend groceries"))
    }

    @Test("A Skylight list rename updates its linked Apple list")
    func skylightRenameUpdatesApple() {
        let action = ReminderListMetadataPlanner.plan(
            appleTitle: "Groceries",
            skylightTitle: "Shopping list",
            link: link,
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(action == .updateApple(title: "Shopping list"))
    }

    @Test("An initial intentional title difference is preserved")
    func initialDifferentTitlesAreNotRelabeled() {
        let action = ReminderListMetadataPlanner.plan(
            appleTitle: "Groceries",
            skylightTitle: "Kitchen list",
            link: ReminderListMetadataLink(
                baselineAppleTitle: "Groceries",
                baselineSkylightTitle: "Kitchen list"
            ),
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(action == nil)
    }

    @Test("Simultaneous title edits respect the selected conflict policy")
    func simultaneousEditsUseConflictPolicy() {
        let action = ReminderListMetadataPlanner.plan(
            appleTitle: "Apple groceries",
            skylightTitle: "Skylight groceries",
            link: link,
            direction: .twoWay,
            conflictPolicy: .skylightWins
        )

        #expect(action == .updateApple(title: "Skylight groceries"))
    }
}
