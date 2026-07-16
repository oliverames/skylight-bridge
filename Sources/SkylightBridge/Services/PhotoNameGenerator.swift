import CoreGraphics
import Foundation
import FoundationModels
import ImageIO

/// Produces short, local display titles for hand-picked Photos assets.
/// The model receives only the image the person just selected and runs entirely
/// on device. No title is written back to Apple Photos.
enum PhotoNameGenerator {
    @available(macOS 27.0, *)
    static func name(for imageData: Data) async -> String? {
        guard case .available = SystemLanguageModel.default.availability,
              let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let session = LanguageModelSession(
            model: .default,
            instructions: """
            Create clear, specific names for a person's selected photos.
            Return only the name, without quotation marks or explanation.
            """
        )

        do {
            let response = try await session.respond(
                options: GenerationOptions(samplingMode: .greedy)
            ) {
                """
                Give this photo a concise, descriptive title of three to seven words.
                Describe visible people, activity, place, or occasion when apparent.
                Do not use the words photo, image, or picture.
                """
                Prompt { Attachment(image) }
            }
            return clean(response.content)
        } catch {
            return nil
        }
    }

    static func clean(_ title: String) -> String? {
        let firstLine = title
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'“”‘’")) ?? ""
        guard !firstLine.isEmpty else { return nil }
        return String(firstLine.prefix(80))
    }
}
