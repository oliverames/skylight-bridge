import Photos
import SwiftUI

struct SelectedPhotoThumbnail: View {
    let assetID: String
    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var requestID: PHImageRequestID?
    @State private var generation = UUID()

    private let side: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Photo preview")
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Photo preview unavailable")
                    .help("This photo is not available in the Photos library on this Mac.")
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear(perform: load)
        .onChange(of: assetID) { load() }
        .onChange(of: displayScale) { load() }
        .onDisappear(perform: cancel)
    }

    private func load() {
        cancel()
        image = nil
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID], options: nil
        ).firstObject else { return }

        isLoading = true
        let currentGeneration = generation
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: side * displayScale, height: side * displayScale),
            contentMode: .aspectFill,
            options: options
        ) { @Sendable result, info in
            let isFinal = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue != true
            Task { @MainActor in
                guard generation == currentGeneration else { return }
                if let result { image = result }
                if isFinal { isLoading = false }
            }
        }
    }

    private func cancel() {
        // Invalidate callbacks already queued on the main actor as well as
        // cancelling PhotoKit's outstanding work when a row leaves the screen.
        generation = UUID()
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        requestID = nil
        isLoading = false
    }
}
