import Foundation
import Testing
@testable import SkylightBridge

struct AppleNotesStoreTests {
    @Test("Every Notes AppleScript repeat loop dereferences its list item")
    func appleScriptsDereferenceListItems() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/SkylightBridge/Services/AppleNotesStore.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var loopsChecked = 0

        for (index, line) in lines.enumerated() {
            guard let marker = line.range(of: "repeat with ") else { continue }
            let remainder = line[marker.upperBound...]
            guard let variable = remainder.split(whereSeparator: \.isWhitespace).first else {
                continue
            }

            loopsChecked += 1
            let expected = "set \(variable) to contents of \(variable)"
            let firstUse = lines[(index + 1)...].first { candidate in
                candidate.contains(variable)
            }
            // Reading a property of an AppleScript list reference yields the
            // reference, not the value. The dereference must therefore be the
            // first use inside this exact loop, not merely present elsewhere.
            #expect(
                firstUse?.trimmingCharacters(in: .whitespaces) == expected,
                "Loop variable '\(variable)' is used before dereferencing"
            )
        }
        #expect(loopsChecked == 8)
    }
}
