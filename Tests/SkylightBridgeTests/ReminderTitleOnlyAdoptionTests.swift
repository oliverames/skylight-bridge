import Foundation
import Testing
@testable import SkylightBridge

struct ReminderTitleOnlyAdoptionTests {
    @Test("Title-only adoption links items whose completion diverged")
    func titleOnlyAdoptionLinksDivergedCompletion() {
        let apple = [
            ReminderSnapshot(id: "apple-1", title: "Milk", notes: nil, isCompleted: true, modifiedAt: Date(timeIntervalSince1970: 100)),
            ReminderSnapshot(id: "apple-2", title: "Bread", notes: nil, isCompleted: false, modifiedAt: Date(timeIntervalSince1970: 100))
        ]
        let skylight = [
            SkylightListItemSnapshot(id: "remote-1", title: "Milk", notes: nil, isCompleted: false, modifiedAt: Date(timeIntervalSince1970: 100)),
            SkylightListItemSnapshot(id: "remote-2", title: "Bread", notes: nil, isCompleted: false, modifiedAt: Date(timeIntervalSince1970: 100))
        ]
        let primaryPairs = ReminderSyncPlanner.adoptionPairs(
            apple: apple,
            skylight: skylight,
            links: []
        )
        #expect(primaryPairs.count == 1)
        #expect(primaryPairs[0].appleID == "apple-2")
        #expect(primaryPairs[0].skylightID == "remote-2")
        let secondaryPairs = ReminderSyncPlanner.titleOnlyAdoptionPairs(
            apple: apple,
            skylight: skylight,
            primaryPairs: primaryPairs,
            links: []
        )
        #expect(secondaryPairs.count == 1)
        #expect(secondaryPairs[0].appleID == "apple-1")
        #expect(secondaryPairs[0].skylightID == "remote-1")
    }

    @Test("Title-only adoption does not duplicate items already adopted by the primary pass")
    func titleOnlyAdoptionExcludesPrimaryMatches() {
        let apple = [
            ReminderSnapshot(id: "apple-1", title: "Milk", notes: nil, isCompleted: false, modifiedAt: Date(timeIntervalSince1970: 100)),
            ReminderSnapshot(id: "apple-2", title: "Bread", notes: nil, isCompleted: false, modifiedAt: Date(timeIntervalSince1970: 100))
        ]
        let skylight = [
            SkylightListItemSnapshot(id: "remote-1", title: "Milk", notes: nil, isCompleted: false, modifiedAt: Date(timeIntervalSince1970: 100)),
            SkylightListItemSnapshot(id: "remote-2", title: "Bread", notes: nil, isCompleted: false, modifiedAt: Date(timeIntervalSince1970: 100))
        ]
        let primaryPairs = ReminderSyncPlanner.adoptionPairs(
            apple: apple,
            skylight: skylight,
            links: []
        )
        #expect(primaryPairs.count == 2)
        let secondaryPairs = ReminderSyncPlanner.titleOnlyAdoptionPairs(
            apple: apple,
            skylight: skylight,
            primaryPairs: primaryPairs,
            links: []
        )
        #expect(secondaryPairs.isEmpty)
    }

    @Test("Title-only adoption returns empty when there are no unlinked items")
    func titleOnlyAdoptionNoUnlinkedItems() {
        let secondaryPairs = ReminderSyncPlanner.titleOnlyAdoptionPairs(
            apple: [],
            skylight: [],
            primaryPairs: [],
            links: []
        )
        #expect(secondaryPairs.isEmpty)
    }

    @Test("Title-only adoption never steals a persisted link")
    func titleOnlyAdoptionExcludesPersistedLinks() {
        let date = Date(timeIntervalSince1970: 100)
        let apple = [
            ReminderSnapshot(
                id: "apple-linked", title: "Milk", notes: nil,
                isCompleted: true, modifiedAt: date
            )
        ]
        let skylight = [
            SkylightListItemSnapshot(
                id: "remote-linked", title: "Milk", notes: nil,
                isCompleted: false, modifiedAt: date
            )
        ]
        let links = [ReminderSyncLink(
            appleID: "apple-linked",
            skylightID: "remote-linked",
            lastAppleModifiedAt: date,
            lastSkylightModifiedAt: date
        )]

        let pairs = ReminderSyncPlanner.titleOnlyAdoptionPairs(
            apple: apple,
            skylight: skylight,
            primaryPairs: [],
            links: links
        )

        #expect(pairs.isEmpty)
    }
}
