import Testing
@testable import SkylightBridge

struct AppleNotesStoreTests {
    @Test("Notes folder traversal dereferences AppleScript list items")
    func folderTraversalDereferencesListItems() {
        #expect(
            AppleNotesStore.noteSelectionHandlers.contains(
                "repeat with folderItem in folderItems\n            set folderItem to contents of folderItem"
            )
        )
        #expect(
            AppleNotesStore.folderEnumerationScript.contains(
                "repeat with folderItem in folderItems\n            set folderItem to contents of folderItem"
            )
        )
    }
}
