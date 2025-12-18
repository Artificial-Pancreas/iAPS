import PhotosUI
import SwiftUI
import UIKit

/// Camera view for AI-powered food analysis - iOS 26 COMPATIBLE
struct AICameraView: View {
    let onImageCaptured: (UIImage) -> Void
    let setRoute: (FoodSearchRoute?) -> Void
    let onCancel: () -> Void

    @State var showingImagePicker = false
    @State var imageSourceType: ImageSourceType = .camera
    @State private var showingTips = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    enum ImageSourceType {
        case camera
        case photoLibrary
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Auto-launch camera interface
                VStack(spacing: 20) {
                    Spacer()

                    // Simple launch message
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 64))
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Better photos = better estimates")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                CameraTipRow(
                                    icon: "sun.max.fill",
                                    title: "Use bright, even light",
                                    detail: "Harsh shadows confuse the AI and dim light can hide textures."
                                )
                                CameraTipRow(
                                    icon: "arrow.2.circlepath",
                                    title: "Clear the area",
                                    detail: "Remove napkins, lids, or packaging that may be misidentified as food."
                                )
                                CameraTipRow(
                                    icon: "square.dashed",
                                    title: "Frame the full meal",
                                    detail: "Make sure every food item is in the frame."
                                )
                                CameraTipRow(
                                    icon: "ruler",
                                    title: "Add a size reference",
                                    detail: "Forks, cups, or hands help AI calculate realistic portions."
                                )
                                CameraTipRow(
                                    icon: "camera.metering.spot",
                                    title: "Shoot from slightly above",
                                    detail: "Keep the camera level to reduce distortion and keep portions proportional."
                                )
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button(action: {
                            setRoute(.camera)
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14))
                                Text("Take a Photo")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack {
                                Image(systemName: "photo.fill")
                                Text("Choose from Library")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }
                        .onChange(of: selectedPhotoItem) {
                            Task {
                                if let data = try? await selectedPhotoItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data)
                                {
                                    await MainActor.run {
                                        onImageCaptured(uiImage)
                                        selectedPhotoItem = nil // Reset selection
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("AI Food Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

struct ModernCameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.navigationBar.tintColor = .systemBlue
        picker.view.tintColor = .systemBlue

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context _: Context) {
        uiViewController.navigationBar.tintColor = .systemBlue
        uiViewController.view.tintColor = .systemBlue
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ModernCameraView

        init(_ parent: ModernCameraView) {
            self.parent = parent
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.onImageCaptured(uiImage)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private struct CameraTipRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
