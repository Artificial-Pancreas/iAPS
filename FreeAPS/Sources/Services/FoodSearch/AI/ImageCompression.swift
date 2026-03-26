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
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func getImageBase64(
        for image: UIImage,
        maxSize: Int,
        maxBytes: Int = 4_800_000
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var currentMaxSize = maxSize
            while currentMaxSize >= 512 {
                let optimizedImage = ImageCompression.resizeImageForAnalysis(image, maxSize: currentMaxSize)

                guard let imageData = optimizedImage.jpegData(compressionQuality: 90) else {
                    throw AIFoodAnalysisError.imageProcessingFailed
                }

                if imageData.count <= maxBytes {
                    return imageData.base64EncodedString()
                }

                currentMaxSize = currentMaxSize * 3 / 4 // reduce by 25% and retry
                print(
                    "image size: \(optimizedImage.size.width)x\(optimizedImage.size.height), data size: \(imageData.count), reducing max dimension to: \(currentMaxSize) and retrying"
                )
            }
            // couldn't make it small enough...
            throw AIFoodAnalysisError.imageProcessingFailed
        }.value
    }
}
