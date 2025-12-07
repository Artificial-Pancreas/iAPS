import CryptoKit
import Foundation
import UIKit

/// Cache for AI analysis results based on image hashing
class ImageAnalysisCache {
    private let cache = NSCache<NSString, CachedAnalysisResult>()
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes

    init() {
        // Configure cache limits
        cache.countLimit = 50 // Maximum 50 cached results
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB limit
    }

    /// Cache an analysis result for the given image
    func cacheResult(_ result: FoodAnalysisResult, for image: UIImage) {
        let imageHash = calculateImageHash(image)
        let cachedResult = CachedAnalysisResult(
            result: result,
            timestamp: Date(),
            imageHash: imageHash
        )

        cache.setObject(cachedResult, forKey: imageHash as NSString)
    }

    /// Get cached result for the given image if available and not expired
    func getCachedResult(for image: UIImage) -> FoodAnalysisResult? {
        let imageHash = calculateImageHash(image)

        guard let cachedResult = cache.object(forKey: imageHash as NSString) else {
            return nil
        }

        // Check if cache entry has expired
        if Date().timeIntervalSince(cachedResult.timestamp) > cacheExpirationTime {
            cache.removeObject(forKey: imageHash as NSString)
            return nil
        }

        return cachedResult.result
    }

    /// Calculate a hash for the image to use as cache key
    private func calculateImageHash(_ image: UIImage) -> String {
        // Convert image to data and calculate SHA256 hash
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return UUID().uuidString
        }

        let hash = imageData.sha256Hash
        return hash
    }

    /// Clear all cached results
    func clearCache() {
        cache.removeAllObjects()
    }
}

/// Wrapper for cached analysis results with metadata
private class CachedAnalysisResult {
    let result: FoodAnalysisResult
    let timestamp: Date
    let imageHash: String

    init(result: FoodAnalysisResult, timestamp: Date, imageHash: String) {
        self.result = result
        self.timestamp = timestamp
        self.imageHash = imageHash
    }
}

/// Extension to calculate SHA256 hash for Data
extension Data {
    var sha256Hash: String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
