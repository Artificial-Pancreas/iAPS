import AVFoundation
import Foundation
import Speech
import SwiftUI

enum SpeechRecognitionState: Equatable {
    case idle
    case requesting
    case listening
    case processing
    case finished(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .listening,
             .processing: true
        default: false
        }
    }
}

@MainActor final class SpeechRecognitionService: ObservableObject {
    @Published var state: SpeechRecognitionState = .idle
    @Published var transcript: String = ""

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Stores fully finalized text from completed recognition segments.
    /// Text is only added here when result.isFinal == true, meaning Apple
    /// has finished all revisions (e.g. "clan" → "clam") for that segment.
    private var finalizedSegments: [String] = []

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    // MARK: - Public API

    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var microphonePermission: AVAudioSession.RecordPermission {
        AVAudioSession.sharedInstance().recordPermission
    }

    func requestPermissions() async -> Bool {
        state = .requesting

        // Request microphone
        let micGranted: Bool = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard micGranted else {
            state = .error(NSLocalizedString("Microphone access is required for voice input.", comment: ""))
            return false
        }

        // Request speech recognition
        let speechGranted: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechGranted else {
            state = .error(NSLocalizedString("Speech recognition permission is required for voice input.", comment: ""))
            return false
        }

        state = .idle
        return true
    }

    func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error(NSLocalizedString("Speech recognition is not available on this device.", comment: ""))
            return
        }

        cleanupAudio()

        finalizedSegments = []
        transcript = ""
        state = .requesting

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error(NSLocalizedString("Failed to set up audio session: ", comment: "") + error.localizedDescription)
            return
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        // Pass nil format — AVAudioEngine will use the input node's native format
        // and handle any necessary conversion. This is the recommended approach
        // for speech recognition and works on both real devices and the Simulator.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        startNewRecognitionTask()

        do {
            audioEngine.prepare()
            try audioEngine.start()
            state = .listening
        } catch {
            state = .error(NSLocalizedString("Failed to start audio recording: ", comment: "") + error.localizedDescription)
            cleanupAudio()
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        audioEngine.inputNode.removeTap(onBus: 0)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        stopListening()
        transcript = ""
        state = .idle
    }

    // MARK: - Private

    private func startNewRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            state = .error(NSLocalizedString("Unable to create speech recognition request.", comment: ""))
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        if speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    // Display the finalized segments + Apple's live partial for the current segment.
                    // The partial text self-corrects in real time (e.g. "clan" → "clam"),
                    // so we never stash partial text — only isFinal text goes into finalizedSegments.
                    let currentPartial = result.bestTranscription.formattedString
                    let prefix = self.finalizedSegments.joined(separator: " ")
                    self.transcript = (prefix.isEmpty ? currentPartial : prefix + " " + currentPartial)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if result.isFinal {
                        // This segment is fully corrected — lock it into the finalized buffer.
                        let finalText = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !finalText.isEmpty {
                            self.finalizedSegments.append(finalText)
                        }

                        // The recognition task ended naturally (e.g. pause detected).
                        // Restart it so the user can keep speaking until they tap "Done".
                        if self.audioEngine.isRunning {
                            self.startNewRecognitionTask()
                        }
                    }
                }

                if let error {
                    let nsError = error as NSError
                    // Ignore cancellation errors (code 216 = task cancelled by us)
                    if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 { return }
                    // Code 209 = no speech detected / timed out — restart the task
                    if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 209 {
                        if self.audioEngine.isRunning {
                            self.startNewRecognitionTask()
                        }
                        return
                    }
                    if self.state == .listening {
                        self.state = .error(error.localizedDescription)
                        self.cleanupAudio()
                    }
                }
            }
        }
    }

    private func finishListening() {
        stopListening()
        let finalText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalText.isEmpty {
            state = .error(NSLocalizedString("No speech detected. Please try again.", comment: ""))
        } else {
            state = .finished(finalText)
        }
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
