import Foundation
import Testing
@testable import SkylightBridge

struct PhotoNameGeneratorTests {
    @Test("Photo titles use one trimmed line and have a reasonable display limit")
    func cleansGeneratedTitle() {
        #expect(PhotoNameGenerator.clean("  \"Family Picnic at the Lake\"  \nMore detail") == "Family Picnic at the Lake")
        #expect(PhotoNameGenerator.clean("   ") == nil)
        #expect(PhotoNameGenerator.clean(String(repeating: "a", count: 100))?.count == 80)
    }

    @Test("Older photo mappings decode without generated photo names")
    func decodesOlderConfiguration() throws {
        let data = Data("""
        {
          "id": "B2E53B31-DC6C-4FAD-8FA1-18E9F23E4C5B",
          "name": "Family Photos",
          "sourceKind": "selectedPhotos",
          "selectedAssetIDs": ["asset-1"],
          "destinationAlbumTitle": "Family"
        }
        """.utf8)

        let mapping = try JSONDecoder().decode(PhotoMapping.self, from: data)

        #expect(mapping.selectedAssetIDs == ["asset-1"])
        #expect(mapping.selectedPhotoNames.isEmpty)
        #expect(mapping.removalPolicy == .removeFromSkylight)
    }

    @Test("Generated photo names persist with their selected asset")
    func roundTripsGeneratedNames() throws {
        var mapping = PhotoMapping()
        mapping.sourceKind = .selectedPhotos
        mapping.selectedAssetIDs = ["asset-1"]
        mapping.selectedPhotoNames = ["asset-1": "Family Picnic at the Lake"]

        let encoded = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(PhotoMapping.self, from: encoded)

        #expect(decoded.selectedPhotoNames == mapping.selectedPhotoNames)
    }
}
