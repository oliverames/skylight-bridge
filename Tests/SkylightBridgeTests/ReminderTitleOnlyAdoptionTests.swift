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
            primaryPairs: primaryPairs
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
            primaryPairs: primaryPairs
        )
        #expect(secondaryPairs.isEmpty)
    }

    @Test("Title-only adoption returns empty when there are no unlinked items")
    func titleOnlyAdoptionNoUnlinkedItems() {
        let secondaryPairs = ReminderSyncPlanner.titleOnlyAdoptionPairs(
            apple: [],
            skylight: [],
            primaryPairs: []
        )
        #expect(secondaryPairs.isEmpty)
    }
}
