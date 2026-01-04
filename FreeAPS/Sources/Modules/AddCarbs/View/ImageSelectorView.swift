import PhotosUI
import SwiftUI
import UIKit

struct ImageSelectorView: View {
    let initialSearchTerm: String?
    let onSave: (UIImage) -> Void
    let onSearch: (String) async -> [String]

    @Environment(\.dismiss) private var dismiss

    @State private var imageURLs: [String] = []
    @State private var isSearching: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var clipboardImage: UIImage?
    @State private var selectedImage: IdentifiableImage?
    @State private var downloadingURL: String?
    @State private var errorMessage: String?

    @State private var searchText: String

    // MARK: - Computed Properties

    private var hasClipboardImage: Bool {
        clipboardImage != nil
    }

    // MARK: - Initialization

    init(
        initialSearchTerm: String? = nil,
        onSave: @escaping (UIImage) -> Void,
        onSearch: @escaping (String) async -> [String]
    ) {
        self.initialSearchTerm = initialSearchTerm
        self.onSave = onSave
        self.onSearch = onSearch
        searchText = initialSearchTerm ?? ""
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Selection options (fixed at top)
                VStack(spacing: 0) {
                    selectionOptionsSection
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    Divider()
                }

                // Scrollable content
                ScrollView {
                    VStack(spacing: 16) {
                        // Error message
                        if let errorMessage = errorMessage {
                            errorBanner(message: errorMessage)
                        }

                        // Search results
                        if isSearching {
                            searchingIndicator
                        } else if !imageURLs.isEmpty {
                            searchResultsGrid
                                .transaction { transaction in
                                    transaction.animation = nil
                                }
                        } else {
                            emptySearchState
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .fullScreenCover(isPresented: $showCamera) {
                ModernCameraView { capturedImage in
                    selectedImage = IdentifiableImage(image: capturedImage)
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem = newItem else { return }
                Task {
                    await loadPhotoPickerImage(from: newItem)
                }
            }
            .fullScreenCover(item: $selectedImage) { identifiableImage in
                ImagePreview(
                    image: identifiableImage.image,
                    onSave: { finalImage in
                        onSave(finalImage)
                        dismiss()
                    },
                    onCancel: {
                        selectedImage = nil
                    }
                )
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            checkClipboard()
        }
        .onReceive(SwiftUI.NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            checkClipboard()
        }
        .onReceive(SwiftUI.NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Check clipboard when app becomes active (catches Handoff scenarios)
            checkClipboard()
        }
        .task {
            // Periodic clipboard check while view is visible
            while !Task.isCancelled {
                checkClipboard()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task {
            if let initialTerm = initialSearchTerm {
                await performSearch(query: initialTerm)
            }
        }
    }

    // MARK: - View Components

    private var searchBar: some View {
        HStack(spacing: 12) {
            // Search text field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))

                TextField("Search for images...", text: $searchText)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        Task { @MainActor in
                            await performSearch(query: searchText)
                        }
                    }

                // Stable trailing content with fixed layout
                ZStack {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !searchText.isEmpty && !isSearching {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                    }
                }
                .frame(width: 20, height: 20)
                .opacity((!searchText.isEmpty || isSearching) ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)

            // Search button
            Button(action: {
                Task { @MainActor in
                    await performSearch(query: searchText)
                }
            }) {
                Text("Search")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(searchText.isEmpty ? .secondary : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(searchText.isEmpty ? Color(.systemGray5) : Color.accentColor)
                    )
            }
            .disabled(searchText.isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var selectionOptionsSection: some View {
        VStack(spacing: 12) {
            // Take Photo button
            Button(action: {
                showCamera = true
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take Photo")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("Capture a new photo with your camera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)

            // Photo library button
            Button(action: {
                showPhotoPicker = true
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose from Library")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("Select and edit a photo from your library")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)

            // Clipboard button (only show if clipboard has image)
            if hasClipboardImage {
                Button(action: {
                    if let image = clipboardImage {
                        selectedImage = IdentifiableImage(image: image)
                    }
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.purple.opacity(0.12))
                                .frame(width: 44, height: 44)

                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Clipboard Image")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text("An image is available in your clipboard")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Show thumbnail of clipboard image
                        if let clipboardImage = clipboardImage {
                            Image(uiImage: clipboardImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchingIndicator: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Searching for images...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No images found")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var searchResultsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search Results")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(imageURLs.count) images")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(imageURLs, id: \.self) { urlString in
                    ImageGridCell(
                        urlString: urlString,
                        isDownloading: downloadingURL == urlString,
                        onTap: {
                            Task {
                                await downloadAndSelectImage(from: urlString)
                            }
                        }
                    )
                }
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
                .foregroundColor(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                withAnimation {
                    errorMessage = nil
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Helper Methods

    private func checkClipboard() {
        guard !showPhotoPicker, !showCamera, selectedImage == nil else { return }
        if UIPasteboard.general.hasImages {
            clipboardImage = UIPasteboard.general.image
        }
    }

    @MainActor private func performSearch(query: String) async {
        guard !query.isEmpty else { return }

        isSearching = true
        errorMessage = nil

        let urls = await onSearch(query)
        imageURLs = urls
        isSearching = false
    }

    private func loadPhotoPickerImage(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data)
            {
                await MainActor.run {
                    selectedImage = IdentifiableImage(image: uiImage)
                    selectedPhotoItem = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load image: \(error.localizedDescription)"
                selectedPhotoItem = nil
            }
        }
    }

    private func downloadAndSelectImage(from urlString: String) async {
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                errorMessage = "Invalid image URL"
            }
            return
        }

        await MainActor.run {
            downloadingURL = urlString
            errorMessage = nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let uiImage = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = IdentifiableImage(image: uiImage)
                    downloadingURL = nil
                }
            } else {
                await MainActor.run {
                    errorMessage = "Failed to create image from downloaded data"
                    downloadingURL = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to download image: \(error.localizedDescription)"
                downloadingURL = nil
            }
        }
    }
}

// MARK: - Image Grid Cell

private struct ImageGridCell: View {
    let urlString: String
    let isDownloading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                ZStack {
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .overlay(
                                        ProgressView()
                                            .controlSize(.small)
                                    )
                            case let .success(image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.width)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                            case .failure:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 24))
                                            .foregroundColor(.secondary)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                    }

                    // Downloading overlay
                    if isDownloading {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.5))
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            )
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Image Preview

private struct ImagePreview: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isCropping = false
    @State private var containerSize: CGSize = .zero
    @State private var cropRect: CGRect = .zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { geometry in
                let calculatedCropRect = calculateCropRect(in: geometry.size)

                ZStack {
                    // Image layer
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    // Prevent zooming out too much
                                    if scale < 0.5 {
                                        withAnimation(.spring(response: 0.3)) {
                                            scale = 0.5
                                            lastScale = 0.5
                                        }
                                    }
                                    // Prevent zooming in too much
                                    if scale > 5.0 {
                                        withAnimation(.spring(response: 0.3)) {
                                            scale = 5.0
                                            lastScale = 5.0
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                let initialScale = calculateInitialScale(
                                    imageSize: image.size,
                                    containerSize: geometry.size,
                                    cropRect: calculatedCropRect
                                )
                                if scale > initialScale * 1.1 { // Allow some tolerance
                                    // Reset to fill crop area
                                    scale = initialScale
                                    lastScale = initialScale
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    // Zoom in
                                    scale = initialScale * 2.0
                                    lastScale = initialScale * 2.0
                                }
                            }
                        }

                    // Crop overlay
                    CropOverlay(cropRect: calculatedCropRect)
                }
                .task(id: geometry.size) {
                    // Wait for valid geometry
                    guard geometry.size.width > 0, geometry.size.height > 0 else { return }

                    // Store these for the toolbar actions
                    containerSize = geometry.size
                    cropRect = calculateCropRect(in: geometry.size)

                    // Only set initial scale once (when scale is still 1.0)
                    if scale == 1.0 {
                        let initialScale = calculateInitialScale(
                            imageSize: image.size,
                            containerSize: geometry.size,
                            cropRect: cropRect
                        )

                        scale = initialScale
                        lastScale = initialScale
                    }
                }
            }

            // UI overlay with proper safe area handling
            VStack {
                // Instructions at top
                HStack(spacing: 8) {
                    Image(systemName: "hand.pinch")
                        .font(.caption)
                    Text("Pinch to zoom • Drag to reposition")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.9))
                .cornerRadius(20)
                .padding(.top, 16)

                Spacer()

                // Bottom buttons
                HStack(spacing: 16) {
                    Button(action: {
                        onCancel()
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.2))
                            )
                    }

                    Button(action: {
                        cropAndSave(containerSize: containerSize, cropRect: cropRect)
                    }) {
                        Group {
                            if isCropping {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text("Use Image")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor)
                        )
                    }
                    .disabled(isCropping)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .padding(.top, 1) // Small padding to trigger safe area
            .padding(.bottom, 1) // Small padding to trigger safe area
        }
    }

    private func calculateCropRect(in size: CGSize) -> CGRect {
        let padding: CGFloat = 40
        let availableWidth = size.width - (padding * 2)
        let availableHeight = size.height - (padding * 2)

        // Make it a square - use the smaller dimension
        let squareSize = min(availableWidth, availableHeight)

        return CGRect(
            x: (size.width - squareSize) / 2,
            y: (size.height - squareSize) / 2,
            width: squareSize,
            height: squareSize
        )
    }

    private func calculateInitialScale(imageSize: CGSize, containerSize: CGSize, cropRect: CGRect) -> CGFloat {
        // Calculate how the image will be sized with aspectRatio(.fit) within the container
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let fitRatio = min(widthRatio, heightRatio)

        // This is the base display size before any scaling
        let baseDisplayWidth = imageSize.width * fitRatio
        let baseDisplayHeight = imageSize.height * fitRatio

        // Calculate how much to scale to FILL the crop square
        // (use max so the shorter side fills, allowing the longer side to be cropped)
        let scaleToFillWidth = cropRect.width / baseDisplayWidth
        let scaleToFillHeight = cropRect.height / baseDisplayHeight

        let finalScale = max(scaleToFillWidth, scaleToFillHeight)

        return finalScale
    }

    private func cropAndSave(containerSize: CGSize, cropRect: CGRect) {
        isCropping = true

        Task {
            if let croppedImage = await cropImage(containerSize: containerSize, cropRect: cropRect) {
                await MainActor.run {
                    onSave(croppedImage)
                }
            }
        }
    }

    private func cropImage(containerSize: CGSize, cropRect: CGRect) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            // Capture values we need from @State
            let currentOffset = await self.offset
            let currentScale = await self.scale

            // Calculate the image size as it appears on screen
            let imageSize = self.image.size

            // Calculate how the image is sized with .fit before scaling
            let widthRatio = containerSize.width / imageSize.width
            let heightRatio = containerSize.height / imageSize.height
            let fitRatio = min(widthRatio, heightRatio)

            let baseDisplayWidth = imageSize.width * fitRatio
            let baseDisplayHeight = imageSize.height * fitRatio

            // Apply the scale effect
            let scaledImageWidth = baseDisplayWidth * currentScale
            let scaledImageHeight = baseDisplayHeight * currentScale

            // Calculate the center of the container
            let centerX = containerSize.width / 2
            let centerY = containerSize.height / 2

            // Position of the top-left corner of the scaled image on screen
            let imageTopLeftX = centerX - (scaledImageWidth / 2) + currentOffset.width
            let imageTopLeftY = centerY - (scaledImageHeight / 2) + currentOffset.height

            // Fixed output size: 512x512 pixels
            let outputPixelSize: CGFloat = 512.0

            // Calculate scale factor from screen points to output pixels
            let scale = outputPixelSize / cropRect.width

            // Create a graphics context for the output (512x512) with alpha channel
            let format = UIGraphicsImageRendererFormat()
            format.opaque = false // Ensure transparency is supported
            format.scale = 1.0 // Use 1.0 since we're already working with pixel dimensions

            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: outputPixelSize, height: outputPixelSize),
                format: format
            )

            return renderer.image { _ in
                // Don't fill with any background - leave transparent
                // The context already has a transparent background because opaque = false

                // Calculate where to draw the image in the output square
                // Map from screen coordinates to output coordinates
                let imageX = (imageTopLeftX - cropRect.minX) * scale
                let imageY = (imageTopLeftY - cropRect.minY) * scale
                let imageWidth = scaledImageWidth * scale
                let imageHeight = scaledImageHeight * scale

                let drawRect = CGRect(
                    x: imageX,
                    y: imageY,
                    width: imageWidth,
                    height: imageHeight
                )

                // Draw the image - transparency will be preserved automatically
                self.image.draw(in: drawRect)
            }
        }.value
    }
}

// MARK: - Crop Overlay

private struct CropOverlay: View {
    let cropRect: CGRect

    var body: some View {
        ZStack {
            // Darkened areas outside crop rect
            GeometryReader { geometry in
                // Top area
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(height: cropRect.minY)

                // Bottom area
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(height: geometry.size.height - cropRect.maxY)
                    .offset(y: cropRect.maxY)

                // Left area
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: cropRect.minX, height: cropRect.height)
                    .offset(x: 0, y: cropRect.minY)

                // Right area
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: geometry.size.width - cropRect.maxX, height: cropRect.height)
                    .offset(x: cropRect.maxX, y: cropRect.minY)
            }

            // Viewfinder corner brackets
            ViewfinderCorners(cropRect: cropRect)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Viewfinder Corners

private struct ViewfinderCorners: View {
    let cropRect: CGRect
    let bracketLength: CGFloat = 30
    let bracketWidth: CGFloat = 4

    var body: some View {
        ZStack {
            // Top-left corner
            Group {
                // Horizontal line extending to the right
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketLength, height: bracketWidth)
                    .position(x: cropRect.minX + bracketLength / 2, y: cropRect.minY)

                // Vertical line extending downward
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketWidth, height: bracketLength)
                    .position(x: cropRect.minX, y: cropRect.minY + bracketLength / 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

            // Top-right corner
            Group {
                // Horizontal line extending to the left
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketLength, height: bracketWidth)
                    .position(x: cropRect.maxX - bracketLength / 2, y: cropRect.minY)

                // Vertical line extending downward
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketWidth, height: bracketLength)
                    .position(x: cropRect.maxX, y: cropRect.minY + bracketLength / 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

            // Bottom-left corner
            Group {
                // Horizontal line extending to the right
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketLength, height: bracketWidth)
                    .position(x: cropRect.minX + bracketLength / 2, y: cropRect.maxY)

                // Vertical line extending upward
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketWidth, height: bracketLength)
                    .position(x: cropRect.minX, y: cropRect.maxY - bracketLength / 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

            // Bottom-right corner
            Group {
                // Horizontal line extending to the left
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketLength, height: bracketWidth)
                    .position(x: cropRect.maxX - bracketLength / 2, y: cropRect.maxY)

                // Vertical line extending upward
                RoundedRectangle(cornerRadius: bracketWidth / 2)
                    .fill(Color.white)
                    .frame(width: bracketWidth, height: bracketLength)
                    .position(x: cropRect.maxX, y: cropRect.maxY - bracketLength / 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
    }
}

/// Wrapper to make UIImage identifiable for use with SwiftUI's sheet(item:)
private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
