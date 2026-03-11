import Foundation
import UIKit

@MainActor class FoodImageStorageManager {
    static let shared = FoodImageStorageManager()

    private let documentsPath: URL
    private let foodItemsPath: URL

    private var imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        return cache
    }()

    private init() {
        documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        foodItemsPath = documentsPath.appendingPathComponent("FoodItems", isDirectory: true)
        try? FileManager.default.createDirectory(at: foodItemsPath, withIntermediateDirectories: true)
    }

    private func fileURL(for itemId: UUID) -> URL {
        foodItemsPath.appendingPathComponent("\(itemId.uuidString).png")
    }

    private func downloadAndCacheImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        if let cachedImage = imageCache.object(forKey: urlString as NSString) {
            return cachedImage
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            let resizedImage = resizeImage(image, maxDimension: 512)
            imageCache.setObject(resizedImage, forKey: urlString as NSString)
            return resizedImage
        } catch {
            print("Failed to download image from \(urlString): \(error)")
            return nil
        }
    }

    func saveImage(_ image: UIImage, for itemId: UUID) async -> String? {
        let resizedImage = resizeImage(image, maxDimension: 512)

        guard let pngData = resizedImage.pngData() else {
            return nil
        }

        let fileURL = fileURL(for: itemId)

        do {
            try pngData.write(to: fileURL)
            let persistentID = "local://\(itemId.uuidString)"
            imageCache.setObject(resizedImage, forKey: persistentID as NSString)
            return persistentID
        } catch {
            print("FoodImageStorageManager: Failed to save image for \(itemId): \(error)")
            return nil
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height

        let newSize: CGSize
        if size.width > size.height {
            guard size.width > maxDimension else { return image }
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            guard size.height > maxDimension else { return image }
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = image.scale

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func getCachedImage(for urlString: String) -> UIImage? {
        imageCache.object(forKey: urlString as NSString)
    }

    func loadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty else { return nil }

        if let cachedImage = imageCache.object(forKey: urlString as NSString) {
            return cachedImage
        }

        if urlString.hasPrefix("local://") {
            let uuidString = String(urlString.dropFirst("local://".count))
            guard let uuid = UUID(uuidString: uuidString) else { return nil }

            let fileURL = fileURL(for: uuid)
            let filePath = fileURL.path(percentEncoded: false)

            guard FileManager.default.fileExists(atPath: filePath),
                  let image = UIImage(contentsOfFile: filePath)
            else {
                return nil
            }

            imageCache.setObject(image, forKey: urlString as NSString)
            return image
        }

        return await downloadAndCacheImage(from: urlString)
    }
}
