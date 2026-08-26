import Testing
@testable import SkylightBridge

struct AppleNotesStoreTests {
    @Test("Every Notes AppleScript repeat loop dereferences its list item")
    func appleScriptsDereferenceListItems() {
        let scripts = [
            AppleNotesStore.noteSelectionHandlers,
            AppleNotesStore.folderEnumerationScript
        ]

        for script in scripts {
            var loopsChecked = 0
            for line in script.split(separator: "\n") {
                guard let marker = line.range(of: "repeat with ") else { continue }
                let remainder = line[marker.upperBound...]
                guard let variable = remainder.split(
                    whereSeparator: \.isWhitespace
                ).first else { continue }

                loopsChecked += 1
                // Reading a property of an AppleScript list reference yields
                // the reference, not the value, so each loop variable must be
                // replaced with its contents before first use.
                #expect(
                    script.contains("set \(variable) to contents of \(variable)"),
                    "Loop variable '\(variable)' is used without dereferencing"
                )
            }
            #expect(loopsChecked > 0)
        }
    }
}
