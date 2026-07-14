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
            lastSkylightModifiedAt: Date(timeIntervalSince1970: 100)
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
            lastSkylightModifiedAt: skylight.modifiedAt
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
}
