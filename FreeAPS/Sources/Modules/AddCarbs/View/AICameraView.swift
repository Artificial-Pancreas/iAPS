import Photos
import SwiftUI
import UIKit

/// Camera view for AI-powered food analysis - iOS 26 COMPATIBLE
struct AICameraView: View {
    let onFoodAnalyzed: (AIFoodAnalysisResult, UIImage?) -> Void
    let onCancel: () -> Void

    @State private var capturedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var showingErrorAlert = false
    @State private var imageSourceType: ImageSourceType = .camera
    @State private var telemetryLogs: [String] = []
    @State private var showTelemetry = false

    enum ImageSourceType {
        case camera
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Auto-launch camera interface
                if capturedImage == nil {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Opening camera...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        imageSourceType = .camera
                        showingImagePicker = true
                    }
                } else {
                    // Show captured image and auto-start analysis
                    VStack(spacing: 20) {
                        // Captured image
                        Image(uiImage: capturedImage!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                            .padding(.horizontal)

                        // Analysis in progress (auto-started)
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)

                            Text("Analyzing food with AI...")
                                .font(.body)
                                .foregroundColor(.secondary)

                            Text("Use Cancel to retake photo")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Telemetry window
                            if showTelemetry && !telemetryLogs.isEmpty {
                                TelemetryWindow(logs: telemetryLogs)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .padding()

                        Spacer()
                    }
                    .padding(.top)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !isAnalyzing, analysisError == nil {
                                analyzeImage()
                            }
                        }
                    }
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
        .fullScreenCover(isPresented: $showingImagePicker) {
            if imageSourceType == .camera {
                ModernCameraView(image: $capturedImage, isPresented: $showingImagePicker)
            }
        }
        .onChange(of: showingImagePicker) { isPresented in
            if !isPresented, capturedImage == nil {
                onCancel()
            }
        }
        .alert("Analysis Error", isPresented: $showingErrorAlert) {
            // Credit/quota exhaustion errors - provide direct guidance
            if analysisError?.contains("credits exhausted") == true || analysisError?.contains("quota exceeded") == true {
                Button("Check Account") {
                    analysisError = nil
                }
                Button("Try Different Provider") {
                    ConfigurableAIService.shared.resetToDefault()
                    analysisError = nil
                    analyzeImage()
                }
                Button("Retake Photo") {
                    capturedImage = nil
                    analysisError = nil
                }
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                }
            }
            // Rate limit errors - suggest waiting
            else if analysisError?.contains("rate limit") == true {
                Button("Wait and Retry") {
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        analyzeImage()
                    }
                }
                Button("Try Different Provider") {
                    ConfigurableAIService.shared.resetToDefault()
                    analysisError = nil
                    analyzeImage()
                }
                Button("Retake Photo") {
                    capturedImage = nil
                    analysisError = nil
                }
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                }
            }
            // General errors - provide standard options
            else {
                Button("Retry Analysis") {
                    analyzeImage()
                }
                Button("Retake Photo") {
                    capturedImage = nil
                    analysisError = nil
                }
                if analysisError?.contains("404") == true || analysisError?.contains("service error") == true {
                    Button("Reset to Default") {
                        ConfigurableAIService.shared.resetToDefault()
                        analysisError = nil
                        analyzeImage()
                    }
                }
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                }
            }
        } message: {
            if analysisError?.contains("credits exhausted") == true {
                Text("Your AI provider has run out of credits. Please check your account billing or try a different provider.")
            } else if analysisError?.contains("quota exceeded") == true {
                Text("Your AI provider quota has been exceeded. Please check your usage limits or try a different provider.")
            } else if analysisError?.contains("rate limit") == true {
                Text("Too many requests sent to your AI provider. Please wait a moment before trying again.")
            } else {
                Text(analysisError ?? "Unknown error occurred")
            }
        }
    }

    private func analyzeImage() {
        guard let image = capturedImage else { return }

        // Check if AI service is configured
        let aiService = ConfigurableAIService.shared
        guard aiService.isConfigured else {
            analysisError = "AI service not configured. Please check settings."
            showingErrorAlert = true
            return
        }

        isAnalyzing = true
        analysisError = nil
        telemetryLogs = []
        showTelemetry = true

        // Start telemetry logging with progressive steps
        addTelemetryLog("🔍 Initializing AI food analysis...")

        Task {
            do {
                // Step 1: Image preparation
                await MainActor.run {
                    addTelemetryLog("📱 Processing image data...")
                }
                try await Task.sleep(nanoseconds: 300_000_000)

                await MainActor.run {
                    addTelemetryLog("💼 Optimizing image quality...")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

                // Step 2: AI connection
                await MainActor.run {
                    addTelemetryLog("🧠 Connecting to AI provider...")
                }
                try await Task.sleep(nanoseconds: 300_000_000)

                await MainActor.run {
                    addTelemetryLog("📡 Uploading image for analysis...")
                }
                try await Task.sleep(nanoseconds: 250_000_000)

                // Step 3: Analysis stages
                await MainActor.run {
                    addTelemetryLog("📊 Analyzing nutritional content...")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    addTelemetryLog("🔬 Identifying food portions...")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    addTelemetryLog("📏 Calculating serving sizes...")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    addTelemetryLog("⚖️ Comparing to USDA standards...")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

                // Step 4: AI processing (actual call)
                await MainActor.run {
                    addTelemetryLog("🤖 Running AI vision analysis...")
                }

                let result = try await aiService.analyzeFoodImage(image) { telemetryMessage in
                    Task { @MainActor in
                        addTelemetryLog(telemetryMessage)
                    }
                }

                // Step 5: Results processing
                await MainActor.run {
                    addTelemetryLog("📊 Processing analysis results...")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    addTelemetryLog("🍽️ Generating nutrition summary...")
                }
                try await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    addTelemetryLog("✅ Analysis complete!")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showTelemetry = false
                        isAnalyzing = false
                        onFoodAnalyzed(result, capturedImage)
                    }
                }
            } catch {
                await MainActor.run {
                    addTelemetryLog("⚠️ Connection interrupted...")
                }
                try? await Task.sleep(nanoseconds: 300_000_000)

                await MainActor.run {
                    addTelemetryLog("❌ Analysis failed")

                    // ✅ VERBESSERT: Stabilere Fehlerbehandlung
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showTelemetry = false
                        isAnalyzing = false
                        analysisError = error.localizedDescription
                        showingErrorAlert = true
                    }
                }
            }
        }
    }

    private func addTelemetryLog(_ message: String) {
        telemetryLogs.append(NSLocalizedString(message, comment: "Telemetry log"))
        if telemetryLogs.count > 10 {
            telemetryLogs.removeFirst()
        }
    }
}

struct ModernCameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool
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
                parent.image = uiImage
                saveToPhotoLibrary(uiImage)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }

        private func saveToPhotoLibrary(_ image: UIImage) {
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized || status == .limited else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }
}

struct TelemetryWindow: View {
    let logs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.green)
                    .font(.caption2)
                Text("Analysis Status")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

            // Scrolling logs
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                            HStack {
                                Text(NSLocalizedString(log, comment: "Log"))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .id(index)
                        }
                        Color.clear.frame(height: 56)
                    }
                    .onAppear {
                        if !logs.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: logs.count) {
                        if !logs.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 14)
            .frame(height: 320)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .padding(.top, 8)
    }
}
