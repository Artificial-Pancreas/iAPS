import Foundation
import UIKit

@MainActor class FoodImageStorageManager {
    static let shared = FoodImageStorageManager()

    private var downloadTasks: [String: Task<UIImage?, Never>] = [:]
    private var imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100 // Store up to 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        return cache
    }()

    private init() {}

    /// Returns the URL for storing an image for a given food item ID
    private func fileURL(for itemId: UUID) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let foodItemsPath = documentsPath.appendingPathComponent("FoodItems", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: foodItemsPath, withIntermediateDirectories: true)

        return foodItemsPath.appendingPathComponent("\(itemId.uuidString).png")
    }

    /// Downloads image from HTTP(S) URL and caches it in memory (does NOT save to disk)
    private func downloadAndCacheImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString), !url.isFileURL else {
            return nil
        }

        // Check cache first
        if let cachedImage = imageCache.object(forKey: urlString as NSString) {
            return cachedImage
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            // Resize image to max 512x512 while preserving aspect ratio
            let resizedImage = resizeImage(image, maxDimension: 512)

            // Cache the resized image
            imageCache.setObject(resizedImage, forKey: urlString as NSString)

            return resizedImage
        } catch {
            print("Failed to download image from \(urlString): \(error)")
            return nil
        }
    }

    /// Saves a UIImage directly to local storage for a food item
    /// - Parameter image: The UIImage to save
    /// - Parameter itemId: The UUID of the food item
    /// - Returns: A persistent identifier string (just the UUID) that can be used to load the image later
    func saveImage(_ image: UIImage, for itemId: UUID) async -> String? {
        // Resize image to max 512x512 while preserving aspect ratio and transparency
        let resizedImage = resizeImage(image, maxDimension: 512)

        // Convert to PNG to preserve transparency
        guard let pngData = resizedImage.pngData() else {
            return nil
        }

        let fileURL = fileURL(for: itemId)

        do {
            try pngData.write(to: fileURL)
            // Return just the UUID string as a persistent identifier
            // We'll reconstruct the full path when loading
            let persistentID = "local://\(itemId.uuidString)"

            // Also cache it in memory using the persistent ID
            imageCache.setObject(resizedImage, forKey: persistentID as NSString)

            return persistentID
        } catch {
            print("FoodImageStorageManager: Failed to save image for \(itemId): \(error)")
            return nil
        }
    }

    /// Resizes a UIImage to fit within a maximum dimension while preserving aspect ratio and transparency
    /// - Parameters:
    ///   - image: The image to resize
    ///   - maxDimension: The maximum width or height
    /// - Returns: The resized image
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height

        var newSize: CGSize
        if size.width > size.height {
            // Landscape
            if size.width > maxDimension {
                newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                return image // Already small enough
            }
        } else {
            // Portrait or square
            if size.height > maxDimension {
                newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
            } else {
                return image // Already small enough
            }
        }

        // Use opaque: false to preserve transparency
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = image.scale

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Gets a cached image for the given URL (from memory cache only, no disk access)
    /// - Parameter urlString: The URL string to fetch the image for
    /// - Returns: The cached UIImage if available, nil otherwise
    func getCachedImage(for urlString: String) -> UIImage? {
        guard let url = URL(string: urlString), !url.isFileURL else {
            return nil
        }
        return imageCache.object(forKey: urlString as NSString)
    }

    /// Loads an image from any source (file:// or http(s):// or local://) with caching
    /// - Parameter urlString: The URL string (file://, http(s)://, or local://UUID)
    /// - Returns: The UIImage if available/loaded, nil otherwise
    func loadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty else {
            return nil
        }

        // Check memory cache first (works for all URL types)
        if let cachedImage = imageCache.object(forKey: urlString as NSString) {
            return cachedImage
        }

        // Handle local:// persistent IDs (new format)
        if urlString.hasPrefix("local://") {
            let uuidString = String(urlString.dropFirst("local://".count))
            guard let uuid = UUID(uuidString: uuidString) else {
                return nil
            }

            let fileURL = fileURL(for: uuid)
            let filePath: String
            if #available(iOS 16.0, *) {
                filePath = fileURL.path(percentEncoded: false)
            } else {
                filePath = fileURL.path
            }

            guard FileManager.default.fileExists(atPath: filePath),
                  let image = UIImage(contentsOfFile: filePath)
            else {
                return nil
            }

            // Cache it in memory for future use
            imageCache.setObject(image, forKey: urlString as NSString)
            return image
        }

        // Handle file:// URLs (legacy format - for backward compatibility)
        guard let url = URL(string: urlString) else {
            return nil
        }

        if url.isFileURL {
            let filePath: String
            if #available(iOS 16.0, *) {
                filePath = url.path(percentEncoded: false)
            } else {
                filePath = url.path
            }

            // Try to extract UUID from the path and use that instead
            if let filename = url.lastPathComponent.components(separatedBy: ".").first,
               let uuid = UUID(uuidString: filename)
            {
                let reconstructedURL = fileURL(for: uuid)
                let reconstructedPath: String
                if #available(iOS 16.0, *) {
                    reconstructedPath = reconstructedURL.path(percentEncoded: false)
                } else {
                    reconstructedPath = reconstructedURL.path
                }

                if FileManager.default.fileExists(atPath: reconstructedPath),
                   let image = UIImage(contentsOfFile: reconstructedPath)
                {
                    // Cache using the original URL string for consistency
                    imageCache.setObject(image, forKey: urlString as NSString)
                    return image
                }
            }

            // Fall back to trying the original path
            guard FileManager.default.fileExists(atPath: filePath),
                  let image = UIImage(contentsOfFile: filePath)
            else {
                return nil
            }

            imageCache.setObject(image, forKey: urlString as NSString)
            return image
        } else {
            // Download from network
            return await downloadAndCacheImage(from: urlString)
        }
    }

    /// Ensures image is available for display (downloads and caches if needed, but does NOT save to disk)
    /// - Parameter urlString: The image URL to resolve
    /// - Returns: The UIImage if successfully downloaded/cached, nil otherwise
    private func resolveImageURL(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString), !url.isFileURL else {
            return nil
        }

        // Check if there's already a download in progress
        if let existingTask = downloadTasks[urlString] {
            return await existingTask.value
        }

        // Check cache
        if let cachedImage = imageCache.object(forKey: urlString as NSString) {
            return cachedImage
        }

        // Create new download task
        let task = Task<UIImage?, Never> {
            let image = await downloadAndCacheImage(from: urlString)
            _ = await MainActor.run {
                self.downloadTasks.removeValue(forKey: urlString)
            }
            return image
        }

        downloadTasks[urlString] = task
        return await task.value
    }

    /// Ensures food item has a local file URL for its image (saves to disk for persistence)
    /// Only use this when explicitly saving a food item to the database
    /// - Downloads from HTTP(S) if needed and saves to disk
    /// - Returns updated food item with file:// URL
    private func ensureLocalImageURL(for foodItem: FoodItemDetailed) async -> FoodItemDetailed {
        guard let imageURL = foodItem.imageURL else {
            return foodItem // No image URL
        }

        guard let url = URL(string: imageURL), !url.isFileURL else {
            return foodItem // Already a file URL
        }

        // Download the image
        guard let image = await resolveImageURL(imageURL) else {
            return foodItem
        }

        // Save to disk
        guard let localURL = await saveImage(image, for: foodItem.id) else {
            return foodItem
        }

        return foodItem.withImageURL(localURL)
    }

    /// Deletes stored image for a food item
    func deleteImage(for itemId: UUID) {
        let fileURL = fileURL(for: itemId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Clears the in-memory image cache
    func clearCache() {
        imageCache.removeAllObjects()
    }
}
