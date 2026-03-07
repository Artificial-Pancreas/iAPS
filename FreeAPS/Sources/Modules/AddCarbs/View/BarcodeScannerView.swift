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
    @State private var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation
    @State private var torchIsOn = false
    @State private var barcodeDetected = false

    var body: some View {
        ZStack {
            // Camera preview — full screen including safe areas
            CameraPreviewView(scanner: scannerService)
                .ignoresSafeArea()

            // Dimmed overlay with transparent cutout — also full screen
            dimmingOverlay
                .ignoresSafeArea()

            // Scanning frame + hint label, centered on screen
            VStack(spacing: 16) {
                scanningFrame
                Text("Position the barcode within the frame")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .opacity(scannerService.isScanning ? 1 : 0)
            }

            // Error card — shown when the service reports an error
            if let error = scannerService.scanError {
                errorOverlay(for: error)
                    .rotationEffect(controlRotation)
                    .animation(.easeInOut(duration: 0.3), value: deviceOrientation)
            }

            // UI chrome: torch top-right, cancel bottom-center, safe-area aware
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    torchButton
                        .rotationEffect(controlRotation)
                        .animation(.easeInOut(duration: 0.3), value: deviceOrientation)
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)

                Spacer()

                Button {
                    scannerService.stopScanning()
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(minWidth: 120)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .rotationEffect(controlRotation)
                .animation(.easeInOut(duration: 0.3), value: deviceOrientation)
                .padding(.bottom, 28)
            }
            .safeAreaPadding()
        }
        .onAppear {
            cancellables.removeAll()
            if scannerService.hasExistingSession && !scannerService.isScanning {
                scannerService.startScanning()
                observeResults()
            } else if scannerService.hasExistingSession {
                scannerService.resetService()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    setupScannerAfterReset()
                }
            } else {
                setupScannerAfterReset()
            }
        }
        .onDisappear {
            scannerService.stopScanning()
        }
        .onReceive(scannerService.$lastScanResult) { result in
            guard result != nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) { barcodeDetected = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.2)) { barcodeDetected = false }
            }
        }
        .onReceive(Foundation.NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let new = UIDevice.current.orientation
            if new.isValidInterfaceOrientation {
                withAnimation(.easeInOut(duration: 0.3)) { deviceOrientation = new }
            }
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Camera Access Required"),
                message: Text("iAPS needs camera access to scan barcodes. Please enable it in Settings."),
                primaryButton: .default(Text("Open Settings")) { openSettings() },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Dimming Overlay

    /// Full-screen dim layer with a transparent rounded cutout for the scanning area.
    private var dimmingOverlay: some View {
        Color.black.opacity(0.55)
            .mask(
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: 250, height: 150)
                            .blendMode(.destinationOut)
                    )
            )
    }

    // MARK: - Scanning Frame

    private var scanningFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    barcodeDetected ? Color.green : Color.white,
                    lineWidth: barcodeDetected ? 3 : 1.5
                )
                .frame(width: 250, height: 150)
                .animation(.easeInOut(duration: 0.15), value: barcodeDetected)

            if barcodeDetected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.green)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else if scannerService.isScanning {
                AnimatedScanLine()
                    .frame(width: 250, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(width: 250, height: 150)
    }

    // MARK: - Error Overlay

    private func errorOverlay(for error: BarcodeScanError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
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

            HStack(spacing: 12) {
                if error == .cameraPermissionDenied {
                    Button("Open Settings") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Try Again") {
                        scannerService.scanError = nil
                        scannerService.resetSession()
                        setupScanner()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Cancel") {
                    scannerService.stopScanning()
                    onCancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 40)
    }

    // MARK: - Torch Button

    private var torchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toggleTorch()
        } label: {
            Image(systemName: torchIsOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(torchIsOn ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Rotation

    private var controlRotation: Angle {
        switch deviceOrientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }

    // MARK: - Setup

    private func setupScannerAfterReset() {
        scannerService.cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        setupScanner()
        observeResults()
    }

    private func observeResults() {
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
                            self.scannerService.startScanning()
                        } else {
                            self.showingPermissionAlert = true
                        }
                    }
                    .store(in: &cancellables)
            } else if scannerService.cameraAuthorizationStatus == .authorized {
                scannerService.startScanning()
            }
        #endif
    }

    // MARK: - Helpers

    private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            torchIsOn = device.torchMode == .on
            device.unlockForConfiguration()
        } catch {
            print("Torch unavailable: \(error)")
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
    @State private var offset: CGFloat = -75

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .green.opacity(0.8), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    offset = 75
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
