import Foundation
import UIKit

enum ImageCompression {
    static func resizeImageForAnalysis(_ image: UIImage, maxSize: Int) -> UIImage {
        let maxDimension = CGFloat(maxSize)

        if image.size.width <= maxDimension, image.size.height <= maxDimension {
            return image
        }

        let scale = maxDimension / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        return resizeImage(image, to: newSize)
    }

    private static func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func getImageBase64(
        for image: UIImage,
        aggressiveImageCompression: Bool,
        maxSize: Int
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let optimizedImage = ImageCompression.resizeImageForAnalysis(image, maxSize: maxSize)
            let compressionQuality = aggressiveImageCompression ? 0.7 : 0.85

            guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
                throw AIFoodAnalysisError.imageProcessingFailed
            }

            return imageData.base64EncodedString()
        }.value
    }
}
