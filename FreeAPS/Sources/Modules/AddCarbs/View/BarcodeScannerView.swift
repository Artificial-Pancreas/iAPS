import AVFoundation
import Combine
import SwiftUI

/// SwiftUI view for barcode scanning with camera preview and overlay
struct BarcodeScannerView: View {
    @ObservedObject private var scannerService = BarcodeScannerService.shared
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) private var dismiss

    let onBarcodeScanned: (String) -> Void
    let onCancel: () -> Void

    @State private var showingPermissionAlert = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var scanningStage: ScanningStage = .scanning

    enum ScanningStage: LocalizedStringKey, CaseIterable {
        case scanning = "Scanning for barcode or QR code..."
        case detected = "Code detected!"
        case error = "Scan failed"
    }

    var body: some View {
        ZStack { // Outer stack - fills whole screen (camera background)
            // Camera preview background - ignores safe area
            CameraPreviewView(scanner: scannerService)
                .ignoresSafeArea()

            ZStack { // Inner stack - respects safe area
                // Scanning overlay
                scanningOverlay()

                // Error overlay
                if let error = scannerService.scanError {
                    errorOverlay(error: error)
                }

                // Top section - flashlight button and status messages
                VStack {
                    HStack {
                        flashlightButton
                            .padding(.horizontal)
                        Spacer()
                    }

                    // Status messages
                    VStack(spacing: 8) {
                        Text(scanningStage.rawValue)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.2), value: scanningStage)

                        if scanningStage == .scanning {
                            Text("Hold steady for best results")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)

                    Spacer()
                }

                // Bottom control buttons overlay
                VStack {
                    Spacer()
                    controlButtonsOverlay()
                }
            }
            .safeAreaPadding() // Make it respect safe area
        }
        .onAppear {
            print("🎥 ========== BarcodeScannerView.onAppear() ==========")
            print("🎥 Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")

            // Clear any existing observers first to prevent duplicates
            cancellables.removeAll()

            // Check if we can reuse existing session or need to reset
            if scannerService.hasExistingSession && !scannerService.isScanning {
                print("🎥 Scanner has existing session but not running, attempting quick restart...")
                // Try to restart existing session first
                scannerService.startScanning()
                setupScannerAfterReset()
            } else if scannerService.hasExistingSession {
                print("🎥 Scanner has existing session and is running, performing reset...")
                scannerService.resetService()

                // Wait a moment for reset to complete before proceeding (reduced delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.setupScannerAfterReset()
                }
            } else {
                setupScannerAfterReset()
            }
        }
        .onDisappear {
            scannerService.stopScanning()
        }
        .alert(isPresented: $showingPermissionAlert) {
            permissionAlert
        }
        // .supportedInterfaceOrientations(.all)
    }

    // MARK: - Subviews

    private func controlButtonsOverlay() -> some View {
        HStack {
            // Cancel button
            Button {
                print("🎥 ========== Cancel button tapped ==========")
                print("🎥 Stopping scanner...")
                scannerService.stopScanning()

                print("🎥 Calling onCancel callback...")
                onCancel()

                print("🎥 Attempting to dismiss view...")
                DispatchQueue.main.async {
                    dismiss()
                }

                print("🎥 Cancel button action complete")
            } label: {
                Text("Cancel")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
            }

            Spacer()

            // Retry button
            Button {
                print("🎥 Retry button tapped")
                scannerService.resetSession()
                setupScanner()
            } label: {
                Text("Retry")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func scanningOverlay() -> some View {
        ZStack {
            // Full screen semi-transparent overlay with cutout
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .mask(
                    Rectangle()
                        .overlay(
                            Rectangle()
                                .frame(width: 250, height: 150)
                                .blendMode(.destinationOut)
                        )
                )

            // Scanning frame positioned at center
            ZStack {
                Rectangle()
                    .stroke(scanningStage == .detected ? Color.green : Color.white, lineWidth: scanningStage == .detected ? 3 : 2)
                    .frame(width: 250, height: 150)
                    .animation(.easeInOut(duration: 0.3), value: scanningStage)

                if scannerService.isScanning && scanningStage != .detected {
                    AnimatedScanLine()
                }

                if scanningStage == .detected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.green)
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: scanningStage)
                }
            }
        }
    }

    private func errorOverlay(error: BarcodeScanError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                if error == .cameraPermissionDenied {
                    Button("Settings") {
                        print("🎥 Settings button tapped")
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(spacing: 8) {
                    Button("Try Again") {
                        print("🎥 Try Again button tapped in error overlay")
                        scannerService.resetSession()
                        setupScanner()
                    }

                    Button("Check Permissions") {
                        print("🎥 Check Permissions button tapped")
                        let status = AVCaptureDevice.authorizationStatus(for: .video)
                        print("🎥 Current system status: \(status)")
                        scannerService.testCameraAccess()

                        // Clear the current error to test button functionality
                        scannerService.scanError = nil

                        // Request permission again if needed
                        if status == .notDetermined {
                            scannerService.requestCameraPermission()
                                .sink { granted in
                                    print("🎥 Permission request result: \(granted)")
                                    if granted {
                                        setupScanner()
                                    }
                                }
                                .store(in: &cancellables)
                        } else if status != .authorized {
                            showingPermissionAlert = true
                        } else {
                            // Permission is granted, try simple setup
                            setupScanner()
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var flashlightButton: some View {
        Button {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            toggleFlashlight()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: isFlashlightOn() ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 22))
                    .foregroundColor(isFlashlightOn() ? .yellow : .white)
            }
        }
    }

    private var permissionAlert: Alert {
        Alert(
            title: Text("Camera Access Required"),
            message: Text("iAPS needs camera access to scan barcodes. Please enable camera access in Settings."),
            primaryButton: .default(Text("Settings")) {
                openSettings()
            },
            secondaryButton: .cancel()
        )
    }

    // MARK: - Methods

    private func setupScannerAfterReset() {
        print("🎥 Setting up scanner after reset...")

        // Get fresh camera authorization status
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("🎥 Camera authorization from system: \(currentStatus)")
        print("🎥 Scanner service authorization: \(scannerService.cameraAuthorizationStatus)")

        // Update scanner service status
        scannerService.cameraAuthorizationStatus = currentStatus
        print("🎥 Updated scanner service authorization to: \(scannerService.cameraAuthorizationStatus)")

        // Test camera access first
        print("🎥 Running camera access test...")
        scannerService.testCameraAccess()

        // Start scanning immediately
        print("🎥 Calling setupScanner()...")
        setupScanner()

        // Listen for scan results
        print("🎥 Setting up scan result observer...")
        scannerService.$lastScanResult
            .compactMap { $0 }
            .removeDuplicates { $0.barcodeString == $1.barcodeString } // Remove duplicate barcodes
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: false) // Throttle rapid scans
            .sink { result in
                print("🎥 ✅ Code result received: \(result.barcodeString) (Type: \(result.barcodeType))")
                self.onBarcodeScanned(result.barcodeString)

                // Clear scan state immediately to prevent rapid duplicate scans
                self.scannerService.clearScanState()
                print("🔍 Cleared scan state immediately to prevent duplicates")
            }
            .store(in: &cancellables)
    }

    private func setupScanner() {
        print("🎥 Setting up scanner, camera status: \(scannerService.cameraAuthorizationStatus)")

        #if targetEnvironment(simulator)
            print("🎥 WARNING: Running in iOS Simulator - barcode scanning not supported")
            // For simulator, immediately show an error
            DispatchQueue.main.async {
                self.scannerService.scanError = BarcodeScanError.cameraNotAvailable
            }
            return
        #else
            guard scannerService.cameraAuthorizationStatus != .denied else {
                print("🎥 Camera access denied, showing permission alert")
                showingPermissionAlert = true
                return
            }

            if scannerService.cameraAuthorizationStatus == .notDetermined {
                print("🎥 Camera permission not determined, requesting...")
                scannerService.requestCameraPermission()
                    .sink { granted in
                        print("🎥 Camera permission granted: \(granted)")
                        if granted {
                            self.startScanning()
                        } else {
                            self.showingPermissionAlert = true
                        }
                    }
                    .store(in: &cancellables)
            } else if scannerService.cameraAuthorizationStatus == .authorized {
                print("🎥 Camera authorized, starting scanning")
                startScanning()
            }
        #endif
    }

    private func startScanning() {
        print("🎥 BarcodeScannerView.startScanning() called")

        // Simply call the service method - observer already set up in onAppear
        scannerService.startScanning()
    }

    private func toggleFlashlight() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch
        else {
            print("🔦 Flashlight not available")
            return
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
            print("🔦 Flashlight toggled to: \(device.torchMode == .on ? "ON" : "OFF")")
        } catch {
            print("🔦 Flashlight unavailable: \(error)")
        }
    }

    private func isFlashlightOn() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return false }
        return device.torchMode == .on
    }

    private func onBarcodeDetected(_ barcode: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            scanningStage = .detected
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            onBarcodeScanned(barcode)
        }
    }

    private func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            print("🎥 ERROR: Could not create settings URL")
            return
        }

        print("🎥 Opening settings URL: \(settingsUrl)")
        UIApplication.shared.open(settingsUrl) { success in
            print("🎥 Settings URL opened successfully: \(success)")
        }
    }
}

// MARK: - Camera Preview

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var scanner: BarcodeScannerService

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        // Only proceed if the view has valid bounds and camera is authorized
        guard uiView.bounds.width > 0, uiView.bounds.height > 0,
              scanner.cameraAuthorizationStatus == .authorized
        else {
            return
        }

        // Check if we already have a preview layer with the same bounds
        let existingLayers = uiView.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer } ?? []

        // If we already have a preview layer with correct bounds, don't recreate
        if let existingLayer = existingLayers.first,
           existingLayer.frame == uiView.bounds
        {
            print("🎥 Preview layer already exists with correct bounds, skipping")
            return
        }

        // Remove any existing preview layers
        for layer in existingLayers {
            layer.removeFromSuperlayer()
        }

        // Create new preview layer
        if let previewLayer = scanner.getPreviewLayer() {
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill

            // Handle rotation
            if let connection = previewLayer.connection {
                if #available(iOS 17.0, *) {
                    // Use the modern videoRotationAngle API
                    // Note: The camera sensor is landscape by default, so we need to rotate based on interface orientation
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        let interfaceOrientation = windowScene.interfaceOrientation
                        let rotationAngle: CGFloat = {
                            switch interfaceOrientation {
                            case .portrait:
                                return 90 // Camera sensor is landscape, rotate 90° for portrait
                            case .portraitUpsideDown:
                                return 270
                            case .landscapeLeft:
                                return 180
                            case .landscapeRight:
                                return 0
                            default:
                                return 90
                            }
                        }()
                        connection.videoRotationAngle = rotationAngle
                        print("🎥 Set video rotation angle: \(rotationAngle)° for interface orientation: \(interfaceOrientation)")
                    }
                } else {
                    // Fallback for iOS 16 and earlier
                    if connection.isVideoOrientationSupported {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            let interfaceOrientation = windowScene.interfaceOrientation
                            switch interfaceOrientation {
                            case .portrait:
                                connection.videoOrientation = .portrait
                            case .portraitUpsideDown:
                                connection.videoOrientation = .portraitUpsideDown
                            case .landscapeLeft:
                                connection.videoOrientation = .landscapeLeft
                            case .landscapeRight:
                                connection.videoOrientation = .landscapeRight
                            default:
                                connection.videoOrientation = .portrait
                            }
                        }
                    }
                }
            }

            uiView.layer.insertSublayer(previewLayer, at: 0)
            print("🎥 Preview layer added to view with frame: \(previewLayer.frame)")
        }
    }
}

// MARK: - Animated Scan Line

/// Animated scanning line overlay
struct AnimatedScanLine: View {
    @State private var animationOffset: CGFloat = -75

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .green, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: animationOffset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                ) {
                    animationOffset = 75
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
    struct BarcodeScannerView_Previews: PreviewProvider {
        static var previews: some View {
            BarcodeScannerView(
                onBarcodeScanned: { barcode in
                    print("Scanned: \(barcode)")
                },
                onCancel: {
                    print("Cancelled")
                }
            )
        }
    }
#endif
