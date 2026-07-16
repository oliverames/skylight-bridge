import CoreGraphics
import Foundation
import Testing
@testable import SkylightBridge

struct ReminderListColorMetadataPlannerTests {
    private let link = ReminderListColorMetadataLink(
        baselineAppleColor: "#2178AF",
        baselineSkylightColor: "#2178AF"
    )

    @Test("An Apple list color updates its linked Skylight list")
    func appleColorUpdatesSkylight() {
        let action = ReminderListColorMetadataPlanner.plan(
            appleColor: "#FD7A33",
            skylightColor: "#2178AF",
            link: link,
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(action == .updateRemote(color: "#FD7A33"))
    }

    @Test("A Skylight list color updates its linked Apple list")
    func skylightColorUpdatesApple() {
        let action = ReminderListColorMetadataPlanner.plan(
            appleColor: "#2178AF",
            skylightColor: "#34C759",
            link: link,
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(action == .updateApple(color: "#34C759"))
    }

    @Test("An Apple color can populate an uncolored Skylight list")
    func appleColorPopulatesSkylight() {
        let action = ReminderListColorMetadataPlanner.plan(
            appleColor: "#FD7A33",
            skylightColor: nil,
            link: ReminderListColorMetadataLink(
                baselineAppleColor: "#2178AF",
                baselineSkylightColor: nil
            ),
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(action == .updateRemote(color: "#FD7A33"))
    }

    @Test("A Skylight color can populate an uncolored Apple list")
    func skylightColorPopulatesApple() {
        let action = ReminderListColorMetadataPlanner.plan(
            appleColor: nil,
            skylightColor: "#34C759",
            link: ReminderListColorMetadataLink(
                baselineAppleColor: nil,
                baselineSkylightColor: "#2178AF"
            ),
            direction: .twoWay,
            conflictPolicy: .newestWins
        )

        #expect(action == .updateApple(color: "#34C759"))
    }

    @Test("List colors round-trip through Skylight's hex format")
    func colorCodecRoundTripsHex() {
        let color = ReminderListColor.cgColor(for: "#5a31f4")

        #expect(ReminderListColor.hex(for: color) == "#5A31F4")
        #expect(ReminderListColor.normalizedHex("invalid") == nil)
    }

    @Test("Older list metadata records decode without color baselines")
    func legacyRecordDecodesWithoutColors() throws {
        let data = Data("""
        {
          "mappingID": "EF10D3A1-7B45-4F81-A85D-101111111111",
          "frameID": "frame-1",
          "appleListID": "apple-list",
          "skylightListID": "skylight-list",
          "lastSyncedAppleTitle": "Groceries",
          "lastSyncedSkylightTitle": "Groceries"
        }
        """.utf8)

        let record = try JSONDecoder().decode(ReminderListSyncRecord.self, from: data)

        #expect(record.lastSyncedAppleColor == nil)
        #expect(record.lastSyncedSkylightColor == nil)
    }
}
