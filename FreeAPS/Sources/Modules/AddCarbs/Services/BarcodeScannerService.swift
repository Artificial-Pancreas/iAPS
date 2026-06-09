import AVFoundation
import Combine
import Foundation
import UIKit

/// Main-actor, observable front end for barcode scanning.
///
/// Owns only the published UI state and the (main-thread) preview layer + health timer.
/// All AVCapture / Vision work lives in ``BarcodeCaptureEngine``, which reports outcomes
/// back via Sendable ``BarcodeScannerEvent`` values handled on the main actor.
@MainActor final class BarcodeScannerService: ObservableObject {
    @Published var lastScanResult: BarcodeScanResult?
    @Published var isScanning: Bool = false
    @Published var scanError: BarcodeScanError?
    @Published var cameraAuthorizationStatus: AVAuthorizationStatus = .notDetermined

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var sessionHealthTimer: Timer?

    private let engine: BarcodeCaptureEngine

    // MARK: - Singleton

    static let shared = BarcodeScannerService()

    private init() {
        engine = BarcodeCaptureEngine()
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        engine.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    // MARK: - Event Handling (main actor)

    private func handle(_ event: BarcodeScannerEvent) {
        switch event {
        case .started:
            isScanning = true
            scanError = nil
            startSessionHealthMonitoring()
        case .stopped:
            isScanning = false
        case let .failed(error):
            scanError = error
            isScanning = false
        case let .result(result):
            lastScanResult = result
        case let .scanError(error):
            scanError = error
        }
    }

    // MARK: - Public Interface

    var hasExistingSession: Bool {
        engine.hasExistingSession
    }

    func focusAtPoint(_ point: CGPoint) {
        engine.focusAtPoint(point)
    }

    func startScanning() {
        let freshStatus = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthorizationStatus = freshStatus

        guard freshStatus == .authorized else {
            if freshStatus == .notDetermined {
                Task {
                    if await requestCameraPermission() {
                        startScanning()
                    } else {
                        scanError = .cameraPermissionDenied
                        isScanning = false
                    }
                }
            } else {
                scanError = .cameraPermissionDenied
                isScanning = false
            }
            return
        }

        engine.startScanning(authorizationStatus: freshStatus)
    }

    func stopScanning() {
        stopSessionHealthMonitoring()
        isScanning = false
        lastScanResult = nil
        previewLayer = nil
        engine.stopScanning()
    }

    /// Tears down the current session so `startScanning()` can rebuild it fresh.
    func resetSession() {
        engine.resetSession()
    }

    func resetService() {
        stopScanning()
        scanError = nil
    }

    func clearScanState() {
        engine.clearScanState()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.lastScanResult = nil
        }
    }

    func requestCameraPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        return granted
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: engine.captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
        }
        return previewLayer
    }

    // MARK: - Private: Session Health Monitoring (main thread)

    private func startSessionHealthMonitoring() {
        sessionHealthTimer?.invalidate()
        sessionHealthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.engine.checkSessionHealth()
        }
    }

    private func stopSessionHealthMonitoring() {
        sessionHealthTimer?.invalidate()
        sessionHealthTimer = nil
    }
}

// MARK: - Testing Support

#if DEBUG
    extension BarcodeScannerService {
        static func mock() -> BarcodeScannerService {
            let scanner = BarcodeScannerService()
            scanner.cameraAuthorizationStatus = .authorized
            return scanner
        }

        func simulateScan(barcode: String) {
            lastScanResult = BarcodeScanResult.sample(barcode: barcode)
            isScanning = false
        }

        func simulateError(_ error: BarcodeScanError) {
            scanError = error
            isScanning = false
        }
    }
#endif
