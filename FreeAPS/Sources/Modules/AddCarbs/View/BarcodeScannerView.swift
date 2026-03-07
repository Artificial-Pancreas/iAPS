import AVFoundation
import Combine
import SwiftUI

struct BarcodeScannerView: View {
    @ObservedObject private var scannerService = BarcodeScannerService.shared
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
        ZStack {
            CameraPreviewView(scanner: scannerService)
                .ignoresSafeArea()

            ZStack {
                scanningOverlay()

                if let error = scannerService.scanError {
                    errorOverlay(error: error)
                }

                VStack {
                    HStack {
                        flashlightButton
                            .padding(.horizontal)
                        Spacer()
                    }

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

                VStack {
                    Spacer()
                    controlButtonsOverlay()
                }
            }
            .safeAreaPadding()
        }
        .onAppear {
            cancellables.removeAll()

            if scannerService.hasExistingSession && !scannerService.isScanning {
                scannerService.startScanning()
                setupScannerAfterReset()
            } else if scannerService.hasExistingSession {
                scannerService.resetService()
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
    }

    // MARK: - Subviews

    private func controlButtonsOverlay() -> some View {
        HStack {
            Button {
                scannerService.stopScanning()
                onCancel()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
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
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(spacing: 8) {
                    Button("Try Again") {
                        scannerService.resetSession()
                        setupScanner()
                    }

                    Button("Check Permissions") {
                        let status = AVCaptureDevice.authorizationStatus(for: .video)
                        scannerService.scanError = nil

                        if status == .notDetermined {
                            scannerService.requestCameraPermission()
                                .sink { granted in
                                    if granted { setupScanner() }
                                }
                                .store(in: &cancellables)
                        } else if status != .authorized {
                            showingPermissionAlert = true
                        } else {
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
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        scannerService.cameraAuthorizationStatus = currentStatus

        setupScanner()

        scannerService.$lastScanResult
            .compactMap { $0 }
            .removeDuplicates { $0.barcodeString == $1.barcodeString }
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: false)
            .sink { result in
                self.onBarcodeScanned(result.barcodeString)
                self.scannerService.clearScanState()
            }
            .store(in: &cancellables)
    }

    private func setupScanner() {
        #if targetEnvironment(simulator)
            scannerService.scanError = BarcodeScanError.cameraNotAvailable
        #else
            guard scannerService.cameraAuthorizationStatus != .denied else {
                showingPermissionAlert = true
                return
            }

            if scannerService.cameraAuthorizationStatus == .notDetermined {
                scannerService.requestCameraPermission()
                    .sink { granted in
                        if granted {
                            self.startScanning()
                        } else {
                            self.showingPermissionAlert = true
                        }
                    }
                    .store(in: &cancellables)
            } else if scannerService.cameraAuthorizationStatus == .authorized {
                startScanning()
            }
        #endif
    }

    private func startScanning() {
        scannerService.startScanning()
    }

    private func toggleFlashlight() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
        } catch {
            print("Flashlight unavailable: \(error)")
        }
    }

    private func isFlashlightOn() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return false }
        return device.torchMode == .on
    }

    private func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsUrl)
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var scanner: BarcodeScannerService

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        guard uiView.bounds.width > 0, uiView.bounds.height > 0,
              scanner.cameraAuthorizationStatus == .authorized
        else { return }

        let existingLayers = uiView.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer } ?? []

        if let existingLayer = existingLayers.first, existingLayer.frame == uiView.bounds {
            return
        }

        for layer in existingLayers {
            layer.removeFromSuperlayer()
        }

        if let previewLayer = scanner.getPreviewLayer() {
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill

            if let connection = previewLayer.connection {
                if #available(iOS 17.0, *) {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        let rotationAngle: CGFloat
                        switch windowScene.interfaceOrientation {
                        case .portrait: rotationAngle = 90
                        case .portraitUpsideDown: rotationAngle = 270
                        case .landscapeLeft: rotationAngle = 180
                        case .landscapeRight: rotationAngle = 0
                        default: rotationAngle = 90
                        }
                        connection.videoRotationAngle = rotationAngle
                    }
                } else {
                    if connection.isVideoOrientationSupported,
                       let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                    {
                        switch windowScene.interfaceOrientation {
                        case .portrait: connection.videoOrientation = .portrait
                        case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                        case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                        case .landscapeRight: connection.videoOrientation = .landscapeRight
                        default: connection.videoOrientation = .portrait
                        }
                    }
                }
            }

            uiView.layer.insertSublayer(previewLayer, at: 0)
        }
    }
}

// MARK: - Animated Scan Line

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
                onBarcodeScanned: { _ in },
                onCancel: {}
            )
        }
    }
#endif
