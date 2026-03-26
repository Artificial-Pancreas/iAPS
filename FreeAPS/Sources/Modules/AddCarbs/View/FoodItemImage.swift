import Foundation
import SwiftUI

struct FoodItemThumbnail: View {
    let imageURL: String?

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if isLoading {
                loadingPlaceholder()
            } else if loadFailed {
                placeholderImage()
            } else {
                Color.clear
                    .frame(width: 60, height: 60)
            }
        }
        .task(id: imageURL) {
            guard let imageURL = imageURL else { return }

            isLoading = true
            loadFailed = false

            if let image = await FoodImageStorageManager.shared.loadImage(from: imageURL) {
                loadedImage = image
                loadFailed = false
            } else {
                loadedImage = nil
                loadFailed = true
            }

            isLoading = false
        }
    }

    private func loadingPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 60)
            .overlay(
                ProgressView()
                    .controlSize(.small)
            )
    }

    private func placeholderImage() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            )
    }
}

struct FoodItemLargeImage: View {
    let imageURL: String?

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isLoading {
                loadingPlaceholder()
            } else if loadFailed {
                placeholderImage()
            } else {
                Color.clear
                    .frame(width: 80, height: 80)
            }
        }
        .task(id: imageURL) {
            guard let imageURL = imageURL else { return }

            isLoading = true
            loadFailed = false

            if let image = await FoodImageStorageManager.shared.loadImage(from: imageURL) {
                loadedImage = image
                loadFailed = false
            } else {
                loadedImage = nil
                loadFailed = true
            }

            isLoading = false
        }
    }

    private func loadingPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: 80, height: 80)
            .overlay(
                ProgressView()
                    .controlSize(.small)
            )
    }

    private func placeholderImage() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            )
    }
}
