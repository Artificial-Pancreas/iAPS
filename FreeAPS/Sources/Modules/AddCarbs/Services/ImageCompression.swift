import Foundation
import UIKit

enum ImageCompression {
    /// Safe async image optimization to prevent main thread blocking
    static func optimizeImageForAnalysisSafely(_ image: UIImage) async -> UIImage {
        await withCheckedContinuation { continuation in
            // Process image on background thread to prevent UI freezing
            DispatchQueue.global(qos: .userInitiated).async {
                let optimized = optimizeImageForAnalysis(image)
                continuation.resume(returning: optimized)
            }
        }
    }

    /// Intelligent image resizing for optimal AI analysis performance
    static func optimizeImageForAnalysis(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024

        // Check if resizing is needed
        if image.size.width <= maxDimension, image.size.height <= maxDimension {
            return image // No resizing needed
        }

        // Calculate new size maintaining aspect ratio
        let scale = maxDimension / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        // Perform high-quality resize
        return resizeImage(image, to: newSize)
    }

    /// High-quality image resizing helper
    private static func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    static func getImageBase64(
        for image: UIImage,
        aggressiveImageCompression: Bool,
        telemetryCallback _: ((String) -> Void)?
    ) throws -> String {
        let optimizedImage = ImageCompression.optimizeImageForAnalysis(image)
        let adaptiveQuality = ImageCompression.adaptiveCompressionQuality(for: optimizedImage)

        let compressionQuality =
            aggressiveImageCompression ? min(0.7, adaptiveQuality) : adaptiveQuality

        guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw AIFoodAnalysisError.imageProcessingFailed
        }
        return imageData.base64EncodedString()
    }

    /// Adaptive image compression based on image size for optimal performance
    static func adaptiveCompressionQuality(for image: UIImage) -> CGFloat {
        let imagePixels = image.size.width * image.size.height

        // Adaptive compression: larger images need more compression for faster uploads
        switch imagePixels {
        case 0 ..< 500_000: // Small images (< 500k pixels)
            return 0.9
        case 500_000 ..< 1_000_000: // Medium images (500k-1M pixels)
            return 0.8
        default: // Large images (> 1M pixels)
            return 0.7
        }
    }
}
