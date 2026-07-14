import Foundation
import Testing
@testable import SkylightBridge

struct ReminderSyncPlannerTests {
    @Test("An unmapped Apple reminder creates a Skylight item")
    func createsRemoteItem() {
        let reminder = ReminderSnapshot(
            id: "apple-1",
            title: "Milk",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )

        let actions = ReminderSyncPlanner.plan(
            apple: [reminder],
            skylight: [],
            links: [],
            direction: .appleToSkylight,
            conflictPolicy: .newestWins
        )

        #expect(actions == [.createRemote(appleID: "apple-1")])
    }

    @Test("A sub-millisecond baseline drift plans no update")
    func toleratesLossyBaselineRoundtrip() {
        // The sealed state file stores dates as Unix seconds; the 1970↔2001
        // epoch conversion can decode a baseline fractionally below the live
        // EventKit date it was copied from. That drift must not read as an edit.
        let liveDate = Date(timeIntervalSinceReferenceDate: 805_000_000.123456789)
        let roundtripped = Date(timeIntervalSince1970: liveDate.timeIntervalSince1970)
            .addingTimeInterval(-0.0005)
        let apple = ReminderSnapshot(
            id: "apple-1",
            title: "Milk",
            notes: nil,
            isCompleted: false,
            modifiedAt: liveDate
        )
        let skylight = SkylightListItemSnapshot(
            id: "remote-1",
            title: "Milk",
            notes: nil,
            isCompleted: false,
            modifiedAt: roundtripped
        )
        let link = ReminderSyncLink(
            appleID: "apple-1",
            skylightID: "remote-1",
            lastAppleModifiedAt: roundtripped,
            lastSkylightModifiedAt: roundtripped,
            baselineTitle: "Milk",
            baselineCompleted: false
        )

        let actions = ReminderSyncPlanner.plan(
            apple: [apple],
            skylight: [skylight],
            links: [link],
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(actions.isEmpty)
    }

    @Test("A newer Skylight completion updates Apple during two-way sync")
    func pullsNewerRemoteCompletion() {
        let apple = ReminderSnapshot(
            id: "apple-1",
            title: "Milk",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let skylight = SkylightListItemSnapshot(
            id: "remote-1",
            title: "Milk",
            notes: nil,
            isCompleted: true,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let link = ReminderSyncLink(
            appleID: "apple-1",
            skylightID: "remote-1",
            lastAppleModifiedAt: Date(timeIntervalSince1970: 100),
            lastSkylightModifiedAt: Date(timeIntervalSince1970: 100),
            baselineTitle: "Milk",
            baselineCompleted: false
        )

        let actions = ReminderSyncPlanner.plan(
            apple: [apple],
            skylight: [skylight],
            links: [link],
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(actions == [.updateApple(appleID: "apple-1", remoteID: "remote-1")])
    }

    @Test("Two-way sync propagates deletion only for previously linked items")
    func propagatesLinkedDeletions() {
        let apple = ReminderSnapshot(
            id: "apple-1",
            title: "Milk",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let skylight = SkylightListItemSnapshot(
            id: "remote-1",
            title: "Milk",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let link = ReminderSyncLink(
            appleID: apple.id,
            skylightID: skylight.id,
            lastAppleModifiedAt: apple.modifiedAt,
            lastSkylightModifiedAt: skylight.modifiedAt,
            baselineTitle: "Milk",
            baselineCompleted: false
        )

        let deletedOnSkylight = ReminderSyncPlanner.plan(
            apple: [apple],
            skylight: [],
            links: [link],
            direction: .twoWay,
            conflictPolicy: .appleWins
        )
        let deletedOnApple = ReminderSyncPlanner.plan(
            apple: [],
            skylight: [skylight],
            links: [link],
            direction: .twoWay,
            conflictPolicy: .appleWins
        )

        #expect(deletedOnSkylight == [.deleteApple(appleID: apple.id)])
        #expect(deletedOnApple == [.deleteRemote(remoteID: skylight.id)])
    }

    @Test("Adoption pairs unlinked items with equal title and completion state")
    func adoptionPairsMatchingItems() {
        let apple = [
            ReminderSnapshot(
                id: "a1",
                title: "Milk",
                notes: nil,
                isCompleted: false,
                modifiedAt: Date(timeIntervalSince1970: 100)
            ),
            ReminderSnapshot(
                id: "a2",
                title: "Milk",
                notes: nil,
                isCompleted: true,
                modifiedAt: Date(timeIntervalSince1970: 100)
            ),
            ReminderSnapshot(
                id: "a3",
                title: "Bread",
                notes: nil,
                isCompleted: false,
                modifiedAt: Date(timeIntervalSince1970: 100)
            )
        ]
        let skylight = [
            SkylightListItemSnapshot(
                id: "s1",
                title: " milk ",
                notes: nil,
                isCompleted: false,
                modifiedAt: Date(timeIntervalSince1970: 100)
            ),
            SkylightListItemSnapshot(
                id: "s2",
                title: "Milk",
                notes: nil,
                isCompleted: false,
                modifiedAt: Date(timeIntervalSince1970: 100)
            )
        ]

        let pairs = ReminderSyncPlanner.adoptionPairs(apple: apple, skylight: skylight, links: [])

        // The pending "Milk" items pair up case- and whitespace-insensitively.
        // The completed Milk and the unmatched Bread stay unpaired, as does the
        // leftover Skylight duplicate.
        #expect(pairs == [ReminderAdoptionPair(appleID: "a1", skylightID: "s1")])
    }

    @Test("Separate additions on each side are both preserved")
    func preservesSeparateAdditions() {
        let apple = ReminderSnapshot(
            id: "apple-new",
            title: "Walk the dog",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let skylight = SkylightListItemSnapshot(
            id: "remote-new",
            title: "Water the plants",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )

        let actions = ReminderSyncPlanner.plan(
            apple: [apple],
            skylight: [skylight],
            links: [],
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(actions == [
            .createRemote(appleID: "apple-new"),
            .createApple(remoteID: "remote-new")
        ])
    }

    @Test("Disjoint field edits merge instead of clobbering")
    func mergesDisjointFieldEdits() {
        // Apple flipped completion; Skylight renamed the item. Newest-wins would
        // discard one edit, but the two changes touch different fields.
        let apple = ReminderSnapshot(
            id: "apple-1",
            title: "Buy milk",
            notes: nil,
            isCompleted: true,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let skylight = SkylightListItemSnapshot(
            id: "remote-1",
            title: "Buy 2% milk",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let link = ReminderSyncLink(
            appleID: "apple-1",
            skylightID: "remote-1",
            lastAppleModifiedAt: Date(timeIntervalSince1970: 100),
            lastSkylightModifiedAt: Date(timeIntervalSince1970: 100),
            baselineTitle: "Buy milk",
            baselineCompleted: false
        )

        let actions = ReminderSyncPlanner.plan(
            apple: [apple],
            skylight: [skylight],
            links: [link],
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(actions == [
            .merge(appleID: "apple-1", remoteID: "remote-1", title: "Buy 2% milk", isCompleted: true)
        ])
    }

    @Test("A true same-field conflict follows the conflict policy")
    func sameFieldConflictFollowsPolicy() {
        let apple = ReminderSnapshot(
            id: "apple-1",
            title: "Apple title",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let skylight = SkylightListItemSnapshot(
            id: "remote-1",
            title: "Skylight title",
            notes: nil,
            isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 300)
        )
        let link = ReminderSyncLink(
            appleID: "apple-1",
            skylightID: "remote-1",
            lastAppleModifiedAt: Date(timeIntervalSince1970: 100),
            lastSkylightModifiedAt: Date(timeIntervalSince1970: 100),
            baselineTitle: "Original title",
            baselineCompleted: false
        )

        let appleWins = ReminderSyncPlanner.plan(
            apple: [apple],
            skylight: [skylight],
            links: [link],
            direction: .twoWay,
            conflictPolicy: .appleWins
        )
        let skylightWins = ReminderSyncPlanner.plan(
            apple: [apple],
            skylight: [skylight],
            links: [link],
            direction: .twoWay,
            conflictPolicy: .skylightWins
        )

        // Both renamed the same field, so the whole record resolves by policy and
        // collapses onto the winning side's one-way update.
        #expect(appleWins == [.updateRemote(appleID: "apple-1", remoteID: "remote-1")])
        #expect(skylightWins == [.updateApple(appleID: "apple-1", remoteID: "remote-1")])
    }
}
