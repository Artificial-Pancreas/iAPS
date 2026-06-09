import AVFoundation
import Foundation
import UIKit
import Vision

/// Events emitted by ``BarcodeCaptureEngine`` from the session queue (or notification callbacks)
/// and consumed on the main actor by ``BarcodeScannerService``.
enum BarcodeScannerEvent: Sendable {
    /// The capture session started (or resumed) and is running.
    case started
    /// The capture session was interrupted / stopped running.
    case stopped
    /// A fatal session problem occurred; scanning should be considered stopped.
    case failed(BarcodeScanError)
    /// A barcode was successfully scanned.
    case result(BarcodeScanResult)
    /// A non-fatal scan error (e.g. unsupported QR); scanning continues.
    case scanError(BarcodeScanError)
}

/// Owns the AVCapture pipeline, Vision processing, and all session-queue state.
///
/// `@unchecked Sendable`: every stored property below is touched only on `sessionQueue`
/// (the AVCapture delegate is set to deliver on it), is an immutable reference, or — for
/// `onEvent` — is assigned once at construction before any scanning begins and only read
/// thereafter. The `captureSession` reference is exposed so the owner can build a preview
/// layer on the main thread, mirroring Apple's AVCam pattern.
final class BarcodeCaptureEngine: NSObject, @unchecked Sendable {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "barcode.scanner.session", qos: .userInitiated)

    // MARK: - Scan State (sessionQueue only)

    private var isProcessingScan = false
    private var recentlyScannedBarcodes: Set<String> = []
    private var lastValidFrameTime = Date()
    private var currentImageOrientation: CGImagePropertyOrientation = .right

    /// Set once by the owner immediately after `init`, then only read.
    var onEvent: (@Sendable(BarcodeScannerEvent) -> Void)?

    // MARK: - Vision

    private lazy var barcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest(completionHandler: handleDetectedBarcodes)
        request.symbologies = [
            .ean8, .ean13, .upce, .code128, .code39, .code93,
            .dataMatrix, .qr, .pdf417, .aztec, .i2of5
        ]
        return request
    }()

    // MARK: - Compiled Patterns

    private static let numericRegex = try! NSRegularExpression(pattern: "^[0-9]+$")
    private static let alphanumericRegex = try! NSRegularExpression(pattern: "^[A-Z0-9]+$")
    private static let embeddedBarcodeRegex = try! NSRegularExpression(pattern: "([0-9]{8,14})")
    private static let gtinRegex = try! NSRegularExpression(pattern: "\\(01\\)([0-9]{12,14})")

    override init() {
        super.init()
        setupNotificationObservers()
    }

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        Foundation.NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        let nc = Foundation.NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        nc.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
        nc.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
        nc.addObserver(
            self,
            selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    @objc private func deviceOrientationChanged() {
        // Called on main thread — store for use on sessionQueue
        let orientation = imageOrientation(for: UIDevice.current.orientation)
        sessionQueue.async { [weak self] in
            self?.currentImageOrientation = orientation
        }
    }

    private func imageOrientation(for deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch deviceOrientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }

    @objc private func sessionWasInterrupted(notification _: NSNotification) {
        onEvent?(.stopped)
    }

    @objc private func sessionInterruptionEnded(notification _: NSNotification) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            Thread.sleep(forTimeInterval: 0.5)
            if !captureSession.isRunning {
                captureSession.startRunning()
                Thread.sleep(forTimeInterval: 0.5)
                onEvent?(captureSession.isRunning ? .started : .failed(.sessionSetupFailed))
            } else {
                onEvent?(.started)
            }
        }
    }

    @objc private func sessionRuntimeError(notification: NSNotification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
            print("Capture session runtime error: \(error.localizedDescription)")
            onEvent?(.failed(.sessionSetupFailed))
        }
    }

    // MARK: - Public Interface (any thread)

    var hasExistingSession: Bool {
        !captureSession.inputs.isEmpty || !captureSession.outputs.isEmpty
    }

    func focusAtPoint(_ point: CGPoint) {
        sessionQueue.async { [weak self] in
            self?.setFocusPoint(point)
        }
    }

    func startScanning(authorizationStatus: AVAuthorizationStatus) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try setupCaptureSession(authorizationStatus: authorizationStatus)
                captureSession.startRunning()
                Thread.sleep(forTimeInterval: 0.3)
                let running = captureSession.isRunning && !captureSession.isInterrupted
                onEvent?(running ? .started : .failed(.sessionSetupFailed))
            } catch let error as BarcodeScanError {
                onEvent?(.failed(error))
            } catch {
                onEvent?(.failed(.sessionSetupFailed))
            }
        }
    }

    func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isProcessingScan = false
            recentlyScannedBarcodes.removeAll()

            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            Thread.sleep(forTimeInterval: 0.3)

            captureSession.beginConfiguration()
            captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            captureSession.outputs.forEach { self.captureSession.removeOutput($0) }
            captureSession.commitConfiguration()
        }
    }

    /// Tears down the current session so `startScanning()` can rebuild it fresh.
    func resetSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if captureSession.isRunning {
                captureSession.stopRunning()
                Thread.sleep(forTimeInterval: 0.5)
            }
            captureSession.beginConfiguration()
            captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            captureSession.outputs.forEach { self.captureSession.removeOutput($0) }
            captureSession.commitConfiguration()
        }
    }

    func clearScanState() {
        sessionQueue.async { [weak self] in
            self?.isProcessingScan = false
            self?.recentlyScannedBarcodes.removeAll()
        }
    }

    func checkSessionHealth() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let timeSinceLastFrame = Date().timeIntervalSince(lastValidFrameTime)
            if timeSinceLastFrame > 10.0, captureSession.isRunning {
                captureSession.stopRunning()
                Thread.sleep(forTimeInterval: 0.5)
                if !captureSession.isInterrupted {
                    captureSession.startRunning()
                    lastValidFrameTime = Date()
                }
            }
            if !captureSession.isRunning {
                onEvent?(.failed(.sessionSetupFailed))
            }
        }
    }

    // MARK: - Private: Session Setup (sessionQueue)

    private func setupCaptureSession(authorizationStatus: AVAuthorizationStatus) throws {
        #if targetEnvironment(simulator)
            throw BarcodeScanError.cameraNotAvailable
        #else

            guard authorizationStatus == .authorized else {
                throw BarcodeScanError.cameraPermissionDenied
            }

            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )

            guard let videoCaptureDevice = discoverySession.devices.first else {
                throw BarcodeScanError.cameraNotAvailable
            }

            do {
                try videoCaptureDevice.lockForConfiguration()

                if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                    videoCaptureDevice.focusMode = .continuousAutoFocus
                } else if videoCaptureDevice.isFocusModeSupported(.autoFocus) {
                    videoCaptureDevice.focusMode = .autoFocus
                }
                if videoCaptureDevice.isFocusPointOfInterestSupported {
                    videoCaptureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                    videoCaptureDevice.exposureMode = .continuousAutoExposure
                } else if videoCaptureDevice.isExposureModeSupported(.autoExpose) {
                    videoCaptureDevice.exposureMode = .autoExpose
                }
                if videoCaptureDevice.isExposurePointOfInterestSupported {
                    videoCaptureDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if videoCaptureDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    videoCaptureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                videoCaptureDevice.unlockForConfiguration()
            } catch {
                print("Failed to configure camera: \(error.localizedDescription)")
            }

            if captureSession.isRunning {
                captureSession.stopRunning()
                Thread.sleep(forTimeInterval: 0.3)
            }

            captureSession.beginConfiguration()
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            captureSession.outputs.forEach { captureSession.removeOutput($0) }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)

                if captureSession.canSetSessionPreset(.high) {
                    captureSession.sessionPreset = .high
                } else if captureSession.canSetSessionPreset(.medium) {
                    captureSession.sessionPreset = .medium
                }

                guard captureSession.canAddInput(videoInput) else {
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.sessionSetupFailed
                }
                captureSession.addInput(videoInput)

                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]

                guard captureSession.canAddOutput(videoOutput) else {
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.sessionSetupFailed
                }
                captureSession.addOutput(videoOutput)
                videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

                captureSession.commitConfiguration()
            } catch let error as BarcodeScanError {
                captureSession.commitConfiguration()
                throw error
            } catch {
                captureSession.commitConfiguration()
                throw BarcodeScanError.sessionSetupFailed
            }
        #endif
    }

    // MARK: - Private: Focus (sessionQueue)

    private func setFocusPoint(_ point: CGPoint) {
        guard let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("Error setting focus point: \(error)")
        }
    }

    // MARK: - Private: Barcode Detection (sessionQueue)

    private func handleDetectedBarcodes(request: VNRequest, error _: Error?) {
        lastValidFrameTime = Date()

        guard let observations = request.results as? [VNBarcodeObservation] else { return }
        guard !isProcessingScan else { return }

        let validBarcodes = observations.compactMap { observation -> BarcodeScanResult? in
            guard let barcodeString = observation.payloadStringValue,
                  !barcodeString.isEmpty,
                  observation.confidence > 0.5
            else { return nil }

            if observation.symbology == .qr {
                let processed = extractProductIdentifier(from: barcodeString) ?? barcodeString
                return BarcodeScanResult(
                    barcodeString: processed,
                    barcodeType: observation.symbology,
                    confidence: observation.confidence,
                    bounds: observation.boundingBox
                )
            } else {
                guard barcodeString.count >= 8, isValidBarcodeFormat(barcodeString) else { return nil }
                return BarcodeScanResult(
                    barcodeString: barcodeString,
                    barcodeType: observation.symbology,
                    confidence: observation.confidence,
                    bounds: observation.boundingBox
                )
            }
        }

        let traditionalBarcodes = validBarcodes.filter { $0.barcodeType != .qr && $0.barcodeType != .dataMatrix }
        let qrCodes = validBarcodes.filter { $0.barcodeType == .qr || $0.barcodeType == .dataMatrix }

        let selectedBarcode: BarcodeScanResult
        if let best = traditionalBarcodes.max(by: { $0.confidence < $1.confidence }) {
            selectedBarcode = best
        } else if let bestQR = qrCodes.max(by: { $0.confidence < $1.confidence }) {
            if isNonFoodQRCode(bestQR.barcodeString) {
                onEvent?(.scanError(.scanningFailed("This QR code is not a food product code and cannot be scanned")))
                return
            }
            selectedBarcode = bestQR
        } else {
            return
        }

        let minimumConfidence: Float = selectedBarcode.barcodeType == .qr ? 0.6 : 0.8
        guard selectedBarcode.confidence >= minimumConfidence else { return }
        guard !selectedBarcode.barcodeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !recentlyScannedBarcodes.contains(selectedBarcode.barcodeString) else { return }

        isProcessingScan = true
        recentlyScannedBarcodes.insert(selectedBarcode.barcodeString)

        sessionQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isProcessingScan = false
        }
        sessionQueue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.recentlyScannedBarcodes.removeAll()
        }

        onEvent?(.result(selectedBarcode))
    }

    // MARK: - Private: Barcode Validation

    private func isValidBarcodeFormat(_ barcode: String) -> Bool {
        let range = NSRange(barcode.startIndex..., in: barcode)
        switch barcode.count {
        case 8,
             12,
             13:
            return Self.numericRegex.firstMatch(in: barcode, range: range) != nil
        case 9 ... 40:
            return Self.alphanumericRegex.firstMatch(in: barcode, range: range) != nil
        default:
            return false
        }
    }

    private func isNonFoodQRCode(_ qrData: String) -> Bool {
        if qrData.hasPrefix("http://") || qrData.hasPrefix("https://") {
            return extractProductIdentifier(from: qrData) == nil
        }
        let nonFoodPatterns = [
            "mailto:", "tel:", "sms:", "wifi:", "geo:", "contact:", "vcard:",
            "youtube.com", "instagram.com", "facebook.com", "twitter.com", "linkedin.com"
        ]
        let lower = qrData.lowercased()
        return nonFoodPatterns.contains { lower.contains($0) }
    }

    private func extractProductIdentifier(from qrData: String) -> String? {
        let range = NSRange(qrData.startIndex..., in: qrData)

        // Direct numeric barcode
        if Self.numericRegex.firstMatch(in: qrData, range: range) != nil,
           qrData.count >= 8, qrData.count <= 14
        {
            return qrData
        }

        // GTIN format: (01)12345678901234
        if qrData.contains("(01)"),
           let match = Self.gtinRegex.firstMatch(in: qrData, range: range),
           let gtinRange = Range(match.range(at: 1), in: qrData)
        {
            return String(qrData[gtinRange])
        }

        // Extract from URL path or query parameters
        if let url = URL(string: qrData) {
            for component in url.pathComponents.reversed() {
                let compRange = NSRange(component.startIndex..., in: component)
                if Self.numericRegex.firstMatch(in: component, range: compRange) != nil,
                   component.count >= 8, component.count <= 14
                {
                    return component
                }
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems
            {
                let productIdKeys = ["id", "product_id", "gtin", "upc", "ean", "barcode"]
                for queryItem in queryItems {
                    if productIdKeys.contains(queryItem.name.lowercased()),
                       let value = queryItem.value,
                       value.count >= 8, value.count <= 14
                    {
                        let vRange = NSRange(value.startIndex..., in: value)
                        if Self.numericRegex.firstMatch(in: value, range: vRange) != nil {
                            return value
                        }
                    }
                }
            }
        }

        // JSON with known product ID fields
        if qrData.hasPrefix("{"), qrData.hasSuffix("}"),
           let data = qrData.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            let idFields = ["gtin", "upc", "ean", "barcode", "product_id", "id", "code", "productId"]
            for field in idFields {
                if let value = json[field] as? String,
                   value.count >= 8, value.count <= 14
                {
                    let vRange = NSRange(value.startIndex..., in: value)
                    if Self.numericRegex.firstMatch(in: value, range: vRange) != nil {
                        return value
                    }
                }
                if let numValue = json[field] as? NSNumber {
                    let stringValue = numValue.stringValue
                    if stringValue.count >= 8, stringValue.count <= 14 {
                        return stringValue
                    }
                }
            }
        }

        // Any embedded numeric sequence of barcode length
        if let match = Self.embeddedBarcodeRegex.firstMatch(in: qrData, range: range),
           let barcodeRange = Range(match.range(at: 1), in: qrData)
        {
            return String(qrData[barcodeRange])
        }

        // Short compact identifier (e.g. proprietary product codes)
        if qrData.count <= 50, !qrData.contains(" "), !qrData.contains("http") {
            return qrData
        }

        return nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension BarcodeCaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard captureSession.isRunning, !isProcessingScan else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard Int.random(in: 0 ..< 3) == 0 else { return }

        lastValidFrameTime = Date()

        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: currentImageOrientation,
            options: [:]
        )
        do {
            try imageRequestHandler.perform([barcodeRequest])
        } catch {
            print("Vision request error: \(error.localizedDescription)")
        }
    }
}
