import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConversionError: Error, LocalizedError, Sendable {
    case invalidMaximumLongEdge
    case invalidJPEGQuality
    case invalidBackgroundColor
    case renderFailed
    case destinationCreationFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidMaximumLongEdge:
            "The maximum image edge must be positive."
        case .invalidJPEGQuality:
            "JPEG quality must be between 0 and 1."
        case .invalidBackgroundColor:
            "Background color components must be between 0 and 1."
        case .renderFailed:
            "Core Image could not render the converted photo."
        case .destinationCreationFailed:
            "Image I/O could not create a JPEG destination."
        case .encodingFailed:
            "Image I/O could not finalize the JPEG."
        }
    }
}

actor ImageConversionService {
    private let context: CIContext
    private let outputColorSpace: CGColorSpace

    init() {
        let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        self.outputColorSpace = outputColorSpace
        context = CIContext(options: [
            .workingColorSpace: outputColorSpace,
            .outputColorSpace: outputColorSpace,
            .highQualityDownsample: true,
            .cacheIntermediates: false
        ])
    }

    func convert(
        _ renderedPhoto: AppleRenderedPhoto,
        options: AppleImageConversionOptions = AppleImageConversionOptions()
    ) throws -> AppleConvertedImage {
        try validate(options)

        let inputWidth = renderedPhoto.image.width
        let inputHeight = renderedPhoto.image.height
        let longEdge = max(inputWidth, inputHeight)
        let scale = min(1, Double(options.maximumLongEdge) / Double(longEdge))
        let outputWidth = max(1, Int((Double(inputWidth) * scale).rounded()))
        let outputHeight = max(1, Int((Double(inputHeight) * scale).rounded()))
        let outputBounds = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

        var image = CIImage(cgImage: renderedPhoto.image)
        if image.extent.origin != .zero {
            image = image.transformed(
                by: CGAffineTransform(
                    translationX: -image.extent.origin.x,
                    y: -image.extent.origin.y
                )
            )
        }
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        image = image.cropped(to: outputBounds)

        let color = options.backgroundColor
        let background = CIImage(
            color: CIColor(
                red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: 1
            )
        ).cropped(to: outputBounds)
        let flattened = image.composited(over: background).cropped(to: outputBounds)

        guard let outputImage = context.createCGImage(
            flattened,
            from: outputBounds,
            format: .RGBA8,
            colorSpace: outputColorSpace
        ) else {
            throw ImageConversionError.renderFailed
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageConversionError.destinationCreationFailed
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: options.jpegQuality,
            kCGImageDestinationOptimizeColorForSharing: true,
            kCGImageDestinationOrientation: 1,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true
        ]
        CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageConversionError.encodingFailed
        }

        let data = mutableData as Data
        let digest = SHA256.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        return AppleConvertedImage(
            assetID: renderedPhoto.asset.id,
            data: data,
            typeIdentifier: UTType.jpeg.identifier,
            pixelWidth: outputWidth,
            pixelHeight: outputHeight,
            sha256: hash
        )
    }

    private func validate(_ options: AppleImageConversionOptions) throws {
        guard options.maximumLongEdge > 0 else {
            throw ImageConversionError.invalidMaximumLongEdge
        }
        guard (0 ... 1).contains(options.jpegQuality) else {
            throw ImageConversionError.invalidJPEGQuality
        }
        let components = [
            options.backgroundColor.red,
            options.backgroundColor.green,
            options.backgroundColor.blue
        ]
        guard components.allSatisfy({ (0 ... 1).contains($0) }) else {
            throw ImageConversionError.invalidBackgroundColor
        }
    }
}
