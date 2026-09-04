import Testing
@testable import SkylightBridge

struct AppleRemindersFetchTests {
    @Test("A missing EventKit result cannot authorize destructive reconciliation")
    func missingFetchThrows() {
        #expect(throws: (any Error).self) {
            try AppleRemindersStore.requiredFetchResult(nil)
        }
    }

    @Test("An explicit empty EventKit result remains a valid empty snapshot")
    func emptyFetchSucceeds() throws {
        #expect(try AppleRemindersStore.requiredFetchResult([]).isEmpty)
    }
}
