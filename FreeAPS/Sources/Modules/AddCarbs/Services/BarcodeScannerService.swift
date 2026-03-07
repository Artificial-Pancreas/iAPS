import AVFoundation
import Combine
import Foundation
import os.log
import UIKit
import Vision

/// Service for barcode scanning using the device camera and Vision framework
class BarcodeScannerService: NSObject, ObservableObject {
    // MARK: - Properties

    /// Published scan results
    @Published var lastScanResult: BarcodeScanResult?

    /// Published scanning state
    @Published var isScanning: Bool = false

    /// Published error state
    @Published var scanError: BarcodeScanError?

    /// Camera authorization status
    @Published var cameraAuthorizationStatus: AVAuthorizationStatus = .notDetermined

    // MARK: - Scanning State Management

    /// Tracks recently scanned barcodes to prevent duplicates
    private var recentlyScannedBarcodes: Set<String> = []

    /// Timer to clear recently scanned barcodes
    private var duplicatePreventionTimer: Timer?

    /// Flag to prevent multiple simultaneous scan processing
    private var isProcessingScan: Bool = false

    /// Session health monitoring
    private var lastValidFrameTime = Date()
    private var sessionHealthTimer: Timer?

    // Camera session components
    private let captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "barcode.scanner.session", qos: .userInitiated)
    private var _previewLayer: AVCaptureVideoPreviewLayer?

    // Vision request for barcode detection
    private lazy var barcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest(completionHandler: handleDetectedBarcodes)
        request.symbologies = [
            .ean8, .ean13, .upce, .code128, .code39, .code93,
            .dataMatrix, .qr, .pdf417, .aztec, .i2of5
        ]
        return request
    }()

    private let log = OSLog(subsystem: "", category: "BarcodeScannerService")

    // MARK: - Public Interface

    /// Shared instance for app-wide use
    static let shared = BarcodeScannerService()

    /// Focus the camera at a specific point
    func focusAtPoint(_ point: CGPoint) {
        sessionQueue.async { [weak self] in
            self?.setFocusPoint(point)
        }
    }

    override init() {
        super.init()
        checkCameraAuthorization()
    }

    @objc private func sessionWasInterrupted(notification _: NSNotification) {
        DispatchQueue.global().async { [weak self] in
            self?.isScanning = false
        }
    }

    @objc private func sessionInterruptionEnded(notification _: NSNotification) {
        sessionQueue.async {
            // Wait a bit before restarting
            Thread.sleep(forTimeInterval: 0.5)

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()

                // Check if it actually started
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.captureSession.isRunning {
                        self.isScanning = true
                        self.scanError = nil
                    } else {
                        self.scanError = BarcodeScanError.sessionSetupFailed
                        self.isScanning = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isScanning = true
                    self.scanError = nil
                }
            }
        }
    }

    @objc private func sessionRuntimeError(notification: NSNotification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
            print("🎥 Runtime error: \(error.localizedDescription)")

            DispatchQueue.global().async { [weak self] in
                self?.scanError = .sessionSetupFailed
                self?.isScanning = false
            }
        }
    }

    /// Start barcode scanning session
    func startScanning() {
        let freshStatus = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthorizationStatus = freshStatus

        guard freshStatus == .authorized else {
            print("🎥 ERROR: Camera not authorized, status: \(freshStatus)")
            DispatchQueue.global().async {
                if freshStatus == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.global().async { [weak self] in
                            if granted {
                                self?.startScanning()
                            } else {
                                self?.scanError = .cameraPermissionDenied
                                self?.isScanning = false
                            }
                        }
                    }
                } else {
                    self.scanError = .cameraPermissionDenied
                    self.isScanning = false
                }
            }
            return
        }

        sessionQueue.async { [weak self] in
            guard let self = self else {
                return
            }

            do {
                try self.setupCaptureSession()

                self.captureSession.startRunning()

                // Wait a moment for the session to start and stabilize
                Thread.sleep(forTimeInterval: 0.3)

                // Check if the session is running and not interrupted
                let isRunningNow = self.captureSession.isRunning
                let isInterrupted = self.captureSession.isInterrupted

                if isRunningNow && !isInterrupted {
                    // Session started successfully
                    DispatchQueue.main.async { [weak self] in
                        self?.isScanning = true
                        self?.scanError = nil

                        // Start session health monitoring
                        self?.startSessionHealthMonitoring()
                    }
                } else {
                    // Session failed to start or was immediately interrupted
                    DispatchQueue.main.async {
                        self.scanError = BarcodeScanError.sessionSetupFailed
                        self.isScanning = false
                    }
                }
            } catch let error as BarcodeScanError {
                print("BarcodeScanError caught during setup: \(error)")
                print("Error description: \(error.localizedDescription)")
                print("Recovery suggestion: \(error.recoverySuggestion ?? "none")")
                DispatchQueue.main.async {
                    self.scanError = error
                    self.isScanning = false
                }
            } catch {
                print("Unknown error caught during setup: \(error)")
                print("Error description: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("Error domain: \(nsError.domain)")
                    print("Error code: \(nsError.code)")
                    print("Error userInfo: \(nsError.userInfo)")
                }
                DispatchQueue.main.async {
                    self.scanError = .sessionSetupFailed
                    self.isScanning = false
                }
            }
        }
    }

    /// Stop barcode scanning session
    func stopScanning() {
        stopSessionHealthMonitoring()

        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
            self?.lastScanResult = nil
        }

        DispatchQueue.global().async { [weak self] in
            self?.isProcessingScan = false
            self?.recentlyScannedBarcodes.removeAll()
        }

        duplicatePreventionTimer?.invalidate()
        duplicatePreventionTimer = nil

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }

            Thread.sleep(forTimeInterval: 0.3)

            self.captureSession.beginConfiguration()

            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }

            for output in self.captureSession.outputs {
                self.captureSession.removeOutput(output)
            }

            self.captureSession.commitConfiguration()

            _previewLayer = nil // ✅ Wichtig für Cleanup
        }
    }

    deinit {
        stopScanning()
    }

    func requestCameraPermission() -> AnyPublisher<Bool, Never> {
        Future<Bool, Never> { [weak self] promise in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                let newStatus = AVCaptureDevice.authorizationStatus(for: .video)

                DispatchQueue.main.async {
                    self?.cameraAuthorizationStatus = newStatus
                    promise(.success(granted))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func clearScanState() {
        DispatchQueue.global().async { [weak self] in
            self?.isProcessingScan = false
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            self.recentlyScannedBarcodes.removeAll()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            self.lastScanResult = nil
        }
    }

    func resetService() {
        stopScanning()

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            Thread.sleep(forTimeInterval: 0.5)

            DispatchQueue.main.async {
                self.lastScanResult = nil
                self.isProcessingScan = false
                self.scanError = nil
                self.recentlyScannedBarcodes.removeAll()

                self.lastValidFrameTime = Date()
            }
        }
    }

    /// Check if the session has existing configuration
    var hasExistingSession: Bool {
        !captureSession.inputs.isEmpty || !captureSession.outputs.isEmpty
    }

    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.setupCaptureSession()

                DispatchQueue.main.async {
                    self.scanError = nil
                }

            } catch let error as BarcodeScanError {
                DispatchQueue.main.async {
                    self.scanError = error
                }
            } catch {
                DispatchQueue.main.async {
                    self.scanError = .sessionSetupFailed
                }
            }
        }
    }

    /// Reset and reinitialize the camera session
    func resetSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Stop current session
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                Thread.sleep(forTimeInterval: 0.5)
            }

            // Clear all inputs and outputs
            self.captureSession.beginConfiguration()
            self.captureSession.inputs.forEach {
                self.captureSession.removeInput($0)
            }
            self.captureSession.outputs.forEach {
                self.captureSession.removeOutput($0)
            }
            self.captureSession.commitConfiguration()

            // Wait longer before attempting to rebuild
            Thread.sleep(forTimeInterval: 0.5)

            do {
                try self.setupCaptureSession()
                DispatchQueue.main.async {
                    self.scanError = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.scanError = .sessionSetupFailed
                }
            }
        }
    }

    /// Get shared video preview layer
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        if _previewLayer == nil {
            _previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            _previewLayer?.videoGravity = .resizeAspectFill
            print("🎥 Created SINGLETON preview layer")
        }
        return _previewLayer
    }

    // MARK: - Private Methods

    private func checkCameraAuthorization() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func setupCaptureSession() throws {
        #if targetEnvironment(simulator)
            throw BarcodeScanError.cameraNotAvailable
        #endif

        guard cameraAuthorizationStatus == .authorized else {
            throw BarcodeScanError.cameraPermissionDenied
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera // ✅ Nur Wide Angle - zuverlässigste
            ],
            mediaType: .video,
            position: .back
        )

        guard let videoCaptureDevice = discoverySession.devices.first else {
            throw BarcodeScanError.cameraNotAvailable
        }

        // Enhanced camera configuration for optimal scanning (like AI camera)
        do {
            try videoCaptureDevice.lockForConfiguration()

            // Enhanced autofocus configuration
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
            } else if videoCaptureDevice.isFocusModeSupported(.autoFocus) {
                videoCaptureDevice.focusMode = .autoFocus
            }

            // Set focus point to center for optimal scanning
            if videoCaptureDevice.isFocusPointOfInterestSupported {
                videoCaptureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }

            // Enhanced exposure settings for better barcode/QR code detection
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
            } else if videoCaptureDevice.isExposureModeSupported(.autoExpose) {
                videoCaptureDevice.exposureMode = .autoExpose
            }

            // Set exposure point to center
            if videoCaptureDevice.isExposurePointOfInterestSupported {
                videoCaptureDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }

            // Configure for optimal performance
            if videoCaptureDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                videoCaptureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            // Set flash to auto for low light conditions
            if videoCaptureDevice.hasFlash {
                AVCapturePhotoSettings().flashMode = .auto
            }

            videoCaptureDevice.unlockForConfiguration()
        } catch {
            print("Failed to configure camera: \(error)")
        }

        // Stop session if running to avoid conflicts
        if captureSession.isRunning {
            captureSession.stopRunning()

            // Wait longer for the session to fully stop
            Thread.sleep(forTimeInterval: 0.3)
        }

        captureSession.beginConfiguration()

        captureSession.inputs.forEach {
            captureSession.removeInput($0)
        }
        captureSession.outputs.forEach {
            captureSession.removeOutput($0)
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)

            // Set appropriate session preset for barcode scanning BEFORE adding inputs
            if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
            } else if captureSession.canSetSessionPreset(.medium) {
                captureSession.sessionPreset = .medium
            } else {
                print("Could not set preset to high or medium, using: \(captureSession.sessionPreset)")
            }

            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                captureSession.commitConfiguration()
                throw BarcodeScanError.sessionSetupFailed
            }

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)

                // Set sample buffer delegate on the session queue
                videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            } else {
                captureSession.commitConfiguration()
                throw BarcodeScanError.sessionSetupFailed
            }

            captureSession.commitConfiguration()
        } catch let error as BarcodeScanError {
            captureSession.commitConfiguration()
            throw error
        } catch {
            if let nsError = error as NSError? {
                print("NSError domain: \(nsError.domain)")
                print("NSError code: \(nsError.code)")
                print("NSError userInfo: \(nsError.userInfo)")
            }

            // Check for specific AVFoundation errors
            if let avError = error as? AVError {
                print("AVError code: \(avError.code.rawValue)")
                print("AVError description: \(avError.localizedDescription)")

                switch avError.code {
                case .deviceNotConnected:
                    print("ERROR: Camera device not connected")
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.cameraNotAvailable
                case .deviceInUseByAnotherApplication:
                    print("ERROR: Camera device in use by another application")
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.sessionSetupFailed
                case .deviceWasDisconnected:
                    print("ERROR: Camera device was disconnected")
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.cameraNotAvailable
                case .mediaServicesWereReset:
                    print("ERROR: Media services were reset")
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.sessionSetupFailed
                default:
                    print("ERROR: \(avError.localizedDescription)")
                }
            }

            captureSession.commitConfiguration()
            throw BarcodeScanError.sessionSetupFailed
        }
    }

    private func handleDetectedBarcodes(request: VNRequest, error: Error?) {
        lastValidFrameTime = Date()

        guard let observations = request.results as? [VNBarcodeObservation] else {
            if let error = error {
                print("Barcode detection failed: \(error.localizedDescription)")
            }
            return
        }

        // Prevent concurrent processing
        guard !isProcessingScan else {
            print("Skipping barcode processing - already processing another scan")
            return
        }

        // Find the best barcode detection with improved filtering
        let validBarcodes = observations.compactMap { observation -> BarcodeScanResult? in
            guard let barcodeString = observation.payloadStringValue,
                  !barcodeString.isEmpty,
                  observation.confidence > 0.5
            else { // Lower confidence for QR codes
                print(
                    "Filtered out barcode: '\(observation.payloadStringValue ?? "nil")' confidence: \(observation.confidence)"
                )
                return nil
            }

            // Handle QR codes differently from traditional barcodes
            if observation.symbology == .qr {
                // For QR codes, try to extract product identifier
                let processedBarcodeString = extractProductIdentifier(from: barcodeString) ?? barcodeString

                return BarcodeScanResult(
                    barcodeString: processedBarcodeString,
                    barcodeType: observation.symbology,
                    confidence: observation.confidence,
                    bounds: observation.boundingBox
                )
            } else {
                // Traditional barcode validation
                guard barcodeString.count >= 8,
                      isValidBarcodeFormat(barcodeString)
                else {
                    print("Invalid traditional barcode format: '\(barcodeString)'")
                    return nil
                }

                return BarcodeScanResult(
                    barcodeString: barcodeString,
                    barcodeType: observation.symbology,
                    confidence: observation.confidence,
                    bounds: observation.boundingBox
                )
            }
        }

        // Prioritize traditional barcodes over QR codes when both are present
        UserDefaults.standard.barcodeSearchProvider = .openFoodFacts

        let bestBarcode = selectBestBarcode(from: validBarcodes)
        guard let selectedBarcode = bestBarcode else {
            return
        }

        // Enhanced validation - only proceed with high-confidence detections
        let minimumConfidence: Float = selectedBarcode.barcodeType == .qr ? 0.6 : 0.8
        guard selectedBarcode.confidence >= minimumConfidence else {
            print("Barcode confidence too low: \(selectedBarcode.confidence) < \(minimumConfidence)")
            return
        }

        // Ensure barcode string is valid and not empty
        guard !selectedBarcode.barcodeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Empty or whitespace-only barcode string detected")
            return
        }

        // Check for duplicates
        guard !recentlyScannedBarcodes.contains(selectedBarcode.barcodeString) else {
            print("Skipping duplicate barcode: \(selectedBarcode.barcodeString)")
            return
        }

        // Mark as processing to prevent duplicates
        isProcessingScan = true

        // Add to recent scans to prevent duplicates
        recentlyScannedBarcodes.insert(selectedBarcode.barcodeString)

        // Publish result on main queue
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            self.lastScanResult = selectedBarcode

            // Reset processing flag after a brief delay
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                self.isProcessingScan = false
            }

            // Clear recently scanned after a longer delay to allow for duplicate detection
            self.duplicatePreventionTimer?.invalidate()
            self.duplicatePreventionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                self.recentlyScannedBarcodes.removeAll()
            }
        }
    }

    /// Validates barcode format to filter out false positives
    private func isValidBarcodeFormat(_ barcode: String) -> Bool {
        // Check for common barcode patterns
        let numericPattern = "^[0-9]+$"
        let alphanumericPattern = "^[A-Z0-9]+$"

        // EAN-13, UPC-A: 12-13 digits
        if barcode.count == 12 || barcode.count == 13 {
            return barcode.range(of: numericPattern, options: .regularExpression) != nil
        }

        // EAN-8, UPC-E: 8 digits
        if barcode.count == 8 {
            return barcode.range(of: numericPattern, options: .regularExpression) != nil
        }

        // Code 128, Code 39: Variable length alphanumeric
        if barcode.count >= 8, barcode.count <= 40 {
            return barcode.range(of: alphanumericPattern, options: .regularExpression) != nil
        }

        // QR codes: Handle various data formats
        if barcode.count >= 10 {
            return isValidQRCodeData(barcode)
        }

        return false
    }

    /// Validates QR code data and extracts product identifiers if present
    private func isValidQRCodeData(_ qrData: String) -> Bool {
        // URL format QR codes (common for food products)
        if qrData.hasPrefix("http://") || qrData.hasPrefix("https://") {
            return URL(string: qrData) != nil
        }

        // JSON format QR codes
        if qrData.hasPrefix("{"), qrData.hasSuffix("}") {
            // Try to parse as JSON to validate structure
            if let data = qrData.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data)
            {
                return true
            }
        }

        // Product identifier formats (various standards)
        // GTIN format: (01)12345678901234
        if qrData.contains("(01)") {
            return true
        }

        // UPC/EAN codes within QR data
        let numericOnlyPattern = "^[0-9]+$"
        if qrData.range(of: numericOnlyPattern, options: .regularExpression) != nil {
            return qrData.count >= 8 && qrData.count <= 14
        }

        // Allow other structured data formats
        if qrData.count <= 500 { // Reasonable size limit for food product QR codes
            return true
        }

        return false
    }

    /// Select the best barcode from detected options, prioritizing traditional barcodes over QR codes
    private func selectBestBarcode(from barcodes: [BarcodeScanResult]) -> BarcodeScanResult? {
        guard !barcodes.isEmpty else { return nil }

        // Separate traditional barcodes from QR codes
        let traditionalBarcodes = barcodes.filter { result in
            result.barcodeType != .qr && result.barcodeType != .dataMatrix
        }
        let qrCodes = barcodes.filter { result in
            result.barcodeType == .qr || result.barcodeType == .dataMatrix
        }

        // If we have traditional barcodes, pick the one with highest confidence
        if !traditionalBarcodes.isEmpty {
            let bestTraditional = traditionalBarcodes.max { $0.confidence < $1.confidence }!
            return bestTraditional
        }

        // Only use QR codes if no traditional barcodes are present
        if !qrCodes.isEmpty {
            let bestQR = qrCodes.max { $0.confidence < $1.confidence }!

            // Check if QR code is actually food-related
            if isNonFoodQRCode(bestQR.barcodeString) {
                // We could show a specific error here, but for now we'll just return nil
                DispatchQueue.global().async {
                    self.scanError = BarcodeScanError
                        .scanningFailed("This QR code is not a food product code and cannot be scanned")
                }
                return nil
            }

            return bestQR
        }

        return nil
    }

    /// Check if a QR code is a non-food QR code (e.g., pointing to a website)
    private func isNonFoodQRCode(_ qrData: String) -> Bool {
        // Check if it's just a URL without any product identifier
        if qrData.hasPrefix("http://") || qrData.hasPrefix("https://") {
            // If we can't extract a product identifier from the URL, it's likely non-food
            return extractProductIdentifier(from: qrData) == nil
        }

        // Check for common non-food QR code patterns
        let nonFoodPatterns = [
            "mailto:",
            "tel:",
            "sms:",
            "wifi:",
            "geo:",
            "contact:",
            "vcard:",
            "youtube.com",
            "instagram.com",
            "facebook.com",
            "twitter.com",
            "linkedin.com"
        ]

        let lowerQRData = qrData.lowercased()
        for pattern in nonFoodPatterns {
            if lowerQRData.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Extracts a usable product identifier from QR code data
    private func extractProductIdentifier(from qrData: String) -> String? {
        print("🔍 Extracting product ID from QR data: '\(qrData.prefix(200))'")

        // If it's already a simple barcode, return as-is
        let numericPattern = "^[0-9]+$"
        if qrData.range(of: numericPattern, options: .regularExpression) != nil,
           qrData.count >= 8, qrData.count <= 14
        {
            print("🔍 Found direct numeric barcode: '\(qrData)'")
            return qrData
        }

        // Extract from GTIN format: (01)12345678901234
        if qrData.contains("(01)") {
            let gtinPattern = "\\(01\\)([0-9]{12,14})"
            if let regex = try? NSRegularExpression(pattern: gtinPattern),
               let match = regex.firstMatch(in: qrData, range: NSRange(qrData.startIndex..., in: qrData)),
               let gtinRange = Range(match.range(at: 1), in: qrData)
            {
                let gtin = String(qrData[gtinRange])
                print("🔍 Extracted GTIN: '\(gtin)'")
                return gtin
            }
        }

        // Extract from URL path (e.g., https://example.com/product/1234567890123)
        if let url = URL(string: qrData) {
            print("🔍 Processing URL: '\(url.absoluteString)'")
            let pathComponents = url.pathComponents
            for component in pathComponents.reversed() {
                if component.range(of: numericPattern, options: .regularExpression) != nil,
                   component.count >= 8, component.count <= 14
                {
                    print("🔍 Extracted from URL path: '\(component)'")
                    return component
                }
            }

            // Check URL query parameters for product IDs
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems
            {
                let productIdKeys = ["id", "product_id", "gtin", "upc", "ean", "barcode"]
                for queryItem in queryItems {
                    if productIdKeys.contains(queryItem.name.lowercased()),
                       let value = queryItem.value,
                       value.range(of: numericPattern, options: .regularExpression) != nil,
                       value.count >= 8, value.count <= 14
                    {
                        print("🔍 Extracted from URL query: '\(value)'")
                        return value
                    }
                }
            }
        }

        // Extract from JSON (look for common product ID fields)
        if qrData.hasPrefix("{"), qrData.hasSuffix("}"),
           let data = qrData.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            print("🔍 Processing JSON QR code")
            // Common field names for product identifiers
            let idFields = ["gtin", "upc", "ean", "barcode", "product_id", "id", "code", "productId"]
            for field in idFields {
                if let value = json[field] as? String,
                   value.range(of: numericPattern, options: .regularExpression) != nil,
                   value.count >= 8, value.count <= 14
                {
                    print("🔍 Extracted from JSON field '\(field)': '\(value)'")
                    return value
                }
                // Also check for numeric values
                if let numValue = json[field] as? NSNumber {
                    let stringValue = numValue.stringValue
                    if stringValue.count >= 8, stringValue.count <= 14 {
                        print("🔍 Extracted from JSON numeric field '\(field)': '\(stringValue)'")
                        return stringValue
                    }
                }
            }
        }

        // Look for embedded barcodes in any text (more flexible extraction)
        let embeddedBarcodePattern = "([0-9]{8,14})"
        if let regex = try? NSRegularExpression(pattern: embeddedBarcodePattern),
           let match = regex.firstMatch(in: qrData, range: NSRange(qrData.startIndex..., in: qrData)),
           let barcodeRange = Range(match.range(at: 1), in: qrData)
        {
            let extractedBarcode = String(qrData[barcodeRange])
            print("🔍 Found embedded barcode: '\(extractedBarcode)'")
            return extractedBarcode
        }

        // If QR code is short enough, try using it directly as a product identifier
        if qrData.count <= 50, !qrData.contains(" "), !qrData.contains("http") {
            print("🔍 Using short QR data directly: '\(qrData)'")
            return qrData
        }

        print("🔍 No product identifier found, returning nil")
        return nil
    }

    // MARK: - Session Health Monitoring

    /// Set focus point for the camera
    private func setFocusPoint(_ point: CGPoint) {
        guard let device = captureSession.inputs.first as? AVCaptureDeviceInput else {
            print("🔍 No camera device available for focus")
            return
        }

        let cameraDevice = device.device

        do {
            try cameraDevice.lockForConfiguration()

            // Set focus point if supported
            if cameraDevice.isFocusPointOfInterestSupported {
                cameraDevice.focusPointOfInterest = point
                print("🔍 Set focus point to: \(point)")
            }

            // Set autofocus mode
            if cameraDevice.isFocusModeSupported(.autoFocus) {
                cameraDevice.focusMode = .autoFocus
                print("🔍 Triggered autofocus at point: \(point)")
            }

            // Set exposure point if supported
            if cameraDevice.isExposurePointOfInterestSupported {
                cameraDevice.exposurePointOfInterest = point
                print("🔍 Set exposure point to: \(point)")
            }

            // Set exposure mode
            if cameraDevice.isExposureModeSupported(.autoExpose) {
                cameraDevice.exposureMode = .autoExpose
                print("🔍 Set auto exposure at point: \(point)")
            }

            cameraDevice.unlockForConfiguration()

        } catch {
            print("🔍 Error setting focus point: \(error)")
        }
    }

    /// Start monitoring session health
    private func startSessionHealthMonitoring() {
        print("🎥 Starting session health monitoring")
        lastValidFrameTime = Date()

        sessionHealthTimer?.invalidate()
        sessionHealthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkSessionHealth()
        }
    }

    /// Stop session health monitoring
    private func stopSessionHealthMonitoring() {
        print("🎥 Stopping session health monitoring")
        sessionHealthTimer?.invalidate()
        sessionHealthTimer = nil
    }

    /// Check if the session is healthy
    private func checkSessionHealth() {
        let timeSinceLastFrame = Date().timeIntervalSince(lastValidFrameTime)

        print("🎥 Health check - seconds since last frame: \(timeSinceLastFrame)")

        // If no frames for more than 10 seconds, session may be stalled
        if timeSinceLastFrame > 10.0, captureSession.isRunning, isScanning {
            print("🎥 ⚠️ Session appears stalled - no frames for \(timeSinceLastFrame) seconds")

            // Attempt to restart the session
            sessionQueue.async { [weak self] in
                guard let self = self else { return }

                print("🎥 Attempting session restart due to stall...")

                // Stop and restart
                self.captureSession.stopRunning()
                Thread.sleep(forTimeInterval: 0.5)

                if !self.captureSession.isInterrupted {
                    self.captureSession.startRunning()
                    self.lastValidFrameTime = Date()
                    print("🎥 Session restarted after stall")
                } else {
                    print("🎥 Cannot restart - session is interrupted")
                }
            }
        }

        // Check session state
        if !captureSession.isRunning, isScanning {
            print("🎥 ⚠️ Session stopped but still marked as scanning")
            DispatchQueue.global().async {
                self.isScanning = false
                self.scanError = BarcodeScanError.sessionSetupFailed
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension BarcodeScannerService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        // Skip processing if already processing a scan or not actively scanning
        guard isScanning, !isProcessingScan else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("🔍 Failed to get pixel buffer from sample")
            return
        }

        // Throttle processing to improve performance - process every 3rd frame
        guard arc4random_uniform(3) == 0 else { return }

        // Update frame time for health monitoring
        lastValidFrameTime = Date()

        // Determine image orientation based on device orientation
        let deviceOrientation = UIDevice.current.orientation
        let imageOrientation: CGImagePropertyOrientation

        switch deviceOrientation {
        case .portrait:
            imageOrientation = .right
        case .portraitUpsideDown:
            imageOrientation = .left
        case .landscapeLeft:
            imageOrientation = .up
        case .landscapeRight:
            imageOrientation = .down
        default:
            imageOrientation = .right
        }

        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: imageOrientation,
            options: [:]
        )

        do {
            try imageRequestHandler.perform([barcodeRequest])
        } catch {
            print("Vision request error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Testing Support

#if DEBUG
    extension BarcodeScannerService {
        /// Create a mock scanner for testing
        static func mock() -> BarcodeScannerService {
            let scanner = BarcodeScannerService()
            scanner.cameraAuthorizationStatus = .authorized
            return scanner
        }

        /// Simulate a successful barcode scan for testing
        func simulateScan(barcode: String) {
            let result = BarcodeScanResult.sample(barcode: barcode)
            DispatchQueue.global().async {
                self.lastScanResult = result
                self.isScanning = false
            }
        }

        /// Simulate a scan error for testing
        func simulateError(_ error: BarcodeScanError) {
            DispatchQueue.global().async {
                self.scanError = error
                self.isScanning = false
            }
        }
    }
#endif
