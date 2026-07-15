import Foundation
import Testing
@testable import SkylightBridge

struct ChoreSyncPlannerTests {
    private let today = Date(timeIntervalSince1970: 1_784_073_600)

    @Test("Adoption matches title and assignee without considering completion")
    func adoptsByTitleAndMember() {
        let apple = appleSnapshot(id: "a", member: "oliver", title: " Water plants ")
        let remote = remoteSnapshot(id: "s", member: "oliver", title: "water plants", status: .complete)
        #expect(ChoreSyncPlanner.adoptionPairs(apple: [apple], skylight: [remote], links: []) == [
            ChoreAdoptionPair(appleID: "a", skylightID: "s")
        ])
    }

    @Test("Separate additions on both sides are preserved")
    func createsBothDirections() {
        let actions = ChoreSyncPlanner.plan(
            apple: [appleSnapshot(id: "a", member: "oliver")],
            skylight: [remoteSnapshot(id: "s", member: ChoreMemberLink.upForGrabsKey)],
            links: [], direction: .twoWay, conflictPolicy: .newestWins,
            today: "2026-07-15", todayDate: today
        )
        #expect(actions == [.createRemote(appleID: "a"), .createApple(seriesID: "s")])
    }

    @Test("A rolled-forward recurring reminder completes today's Skylight occurrence")
    func detectsAppleRollForward() {
        let prior = today
        let next = today.addingTimeInterval(86_400)
        let apple = appleSnapshot(id: "a", member: "oliver", due: next)
        let remote = remoteSnapshot(id: "s", member: "oliver", status: .pending)
        let link = link(baselineDue: prior)
        let actions = ChoreSyncPlanner.plan(
            apple: [apple], skylight: [remote], links: [link], direction: .twoWay,
            conflictPolicy: .newestWins, today: "2026-07-15", todayDate: today
        )
        #expect(actions.contains(.completeRemote(seriesID: "s", status: .complete)))
    }

    @Test("A completed Skylight occurrence completes Apple once")
    func completesAppleOnce() {
        let apple = appleSnapshot(id: "a", member: "oliver", due: today)
        let remote = remoteSnapshot(id: "s", member: "oliver", status: .complete)
        let first = ChoreSyncPlanner.plan(
            apple: [apple], skylight: [remote], links: [link()], direction: .twoWay,
            conflictPolicy: .newestWins, today: "2026-07-15", todayDate: today
        )
        let second = ChoreSyncPlanner.plan(
            apple: [apple], skylight: [remote],
            links: [link(completedDay: "2026-07-15")], direction: .twoWay,
            conflictPolicy: .newestWins, today: "2026-07-15", todayDate: today
        )
        #expect(first.contains(.completeApple(appleID: "a", completed: true)))
        #expect(!second.contains(.completeApple(appleID: "a", completed: true)))
    }

    @Test("Two-way deletion removes the surviving linked side")
    func propagatesDeletion() {
        let deletedRemote = ChoreSyncPlanner.plan(
            apple: [appleSnapshot(id: "a", member: "oliver")], skylight: [],
            links: [link()], direction: .twoWay, conflictPolicy: .newestWins,
            today: "2026-07-15", todayDate: today
        )
        let deletedApple = ChoreSyncPlanner.plan(
            apple: [], skylight: [remoteSnapshot(id: "s", member: "oliver")],
            links: [link()], direction: .twoWay, conflictPolicy: .newestWins,
            today: "2026-07-15", todayDate: today
        )
        #expect(deletedRemote == [.deleteApple(appleID: "a")])
        #expect(deletedApple == [.deleteRemote(seriesID: "s")])
    }

    @Test("A Skylight reopen rewinds an already advanced Apple occurrence")
    func reopensAppleOccurrence() {
        let apple = appleSnapshot(
            id: "a",
            member: "oliver",
            due: today.addingTimeInterval(86_400)
        )
        let remote = remoteSnapshot(id: "s", member: "oliver", status: .pending)
        let actions = ChoreSyncPlanner.plan(
            apple: [apple], skylight: [remote],
            links: [link(baselineDue: today, completedDay: "2026-07-15")],
            direction: .twoWay, conflictPolicy: .newestWins,
            today: "2026-07-15", todayDate: today
        )
        #expect(actions.contains(.completeApple(appleID: "a", completed: false)))
    }

    @Test("A degraded Skylight time slot does not cause a content update loop")
    func degradedRecurrenceDoesNotChurn() {
        let apple = appleSnapshot(id: "a", member: "oliver", due: today)
        let remote = remoteSnapshot(id: "s", member: "oliver")
        let degradedLink = ChoreSyncLink(
            appleID: "a", skylightID: "s", memberKey: "oliver",
            lastAppleModifiedAt: today, lastSkylightModifiedAt: today,
            baselineTitle: "Water plants", baselineNotes: nil,
            baselineRecurrence: "FREQ=DAILY;INTERVAL=1;BYHOUR=6",
            baselineDueDate: today, baselineCompletedInstanceDate: nil,
            recurrenceDegraded: true
        )
        let actions = ChoreSyncPlanner.plan(
            apple: [apple], skylight: [remote], links: [degradedLink],
            direction: .twoWay, conflictPolicy: .newestWins,
            today: "2026-07-15", todayDate: today
        )
        #expect(actions.isEmpty)
    }

    private func appleSnapshot(
        id: String,
        member: String,
        title: String = "Water plants",
        due: Date? = nil
    ) -> ChoreReminderSnapshot {
        ChoreReminderSnapshot(
            id: id, listID: "list", memberKey: member, title: title, notes: nil,
            isCompleted: false, dueDate: due,
            recurrence: ParsedRecurrenceRule(frequency: .daily),
            recurrenceUnsupported: false, modifiedAt: today
        )
    }

    private func remoteSnapshot(
        id: String,
        member: String,
        title: String = "Water plants",
        status: SkylightChoreStatus = .pending
    ) -> SkylightChoreSnapshot {
        SkylightChoreSnapshot(
            id: id, title: title, notes: nil, memberKey: member,
            recurrenceRaw: ["FREQ=DAILY"],
            recurrence: ParsedRecurrenceRule(frequency: .daily),
            recurrenceUnsupported: false, todayStatus: status,
            startDate: today, modifiedAt: today
        )
    }

    private func link(
        baselineDue: Date? = nil,
        completedDay: String? = nil
    ) -> ChoreSyncLink {
        ChoreSyncLink(
            appleID: "a", skylightID: "s", memberKey: "oliver",
            lastAppleModifiedAt: today, lastSkylightModifiedAt: today,
            baselineTitle: "Water plants", baselineNotes: nil,
            baselineRecurrence: "FREQ=DAILY;INTERVAL=1",
            baselineDueDate: baselineDue,
            baselineCompletedInstanceDate: completedDay,
            recurrenceDegraded: false
        )
    }
}
