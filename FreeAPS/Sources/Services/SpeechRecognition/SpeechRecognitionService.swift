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

@MainActor final class SpeechRecognitionService: NSObject, ObservableObject {
    @Published var state: SpeechRecognitionState = .idle
    @Published var transcript: String = ""

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let audioLock = NSLock()
    private var delegateProxy: SpeechRecognitionTaskDelegateProxy?

    /// Stores fully finalized text from completed recognition segments.
    /// Text is only added here when result.isFinal == true, meaning Apple
    /// has finished all revisions (e.g. "clan" → "clam") for that segment.
    private var finalizedSegments: [String] = []

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        super.init()
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
        if AVAudioSession.sharedInstance().recordPermission == .granted,
           SFSpeechRecognizer.authorizationStatus() == .authorized
        {
            state = .idle
            return true
        }

        state = .requesting

        // Request microphone
        let micGranted: Bool = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    continuation.resume(returning: granted)
                }
            }
        }

        guard micGranted else {
            state = .error(NSLocalizedString("Microphone access is required for voice input.", comment: ""))
            return false
        }

        // Request speech recognition
        let speechGranted: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    continuation.resume(returning: status == .authorized)
                }
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

        cleanupAudio(deactivateSession: false)

        finalizedSegments = []
        transcript = ""
        state = .requesting

        Task {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try await Task.detached(priority: .userInitiated) {
                    try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                }.value
            } catch {
                state = .error(
                    NSLocalizedString("Failed to set up audio session: ", comment: "") + error
                        .localizedDescription
                )
                return
            }

            startNewRecognitionTask()

            guard let request = recognitionRequest else { return }

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)

            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else { return }

            let lock = audioLock
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { @Sendable buffer, _ in
                lock.withLock {
                    request.append(buffer)
                }
            }

            do {
                audioEngine.prepare()
                try audioEngine.start()
                state = .listening
            } catch {
                state = .error(
                    NSLocalizedString("Failed to start audio recording: ", comment: "") + error
                        .localizedDescription
                )
                cleanupAudio()
            }
        }
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)

        if audioEngine.isRunning {
            audioEngine.stop()
            audioLock.withLock {
                recognitionRequest?.endAudio()
            }
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        Task.detached(priority: .background) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
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

        let proxy = SpeechRecognitionTaskDelegateProxy(
            onHypothesize: { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let prefix = self.finalizedSegments.joined(separator: " ")
                    self.transcript = (prefix.isEmpty ? text : prefix + " " + text)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            },
            onFinish: { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalText.isEmpty {
                        self.finalizedSegments.append(finalText)
                    }

                    // The recognition task ended naturally (e.g. pause detected).
                    // Restart it so the user can keep speaking until they tap "Done".
                    if self.audioEngine.isRunning {
                        self.startNewRecognitionTask()
                    }
                }
            },
            onComplete: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let error = error {
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
        )
        delegateProxy = proxy
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, delegate: proxy)
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

    private func cleanupAudio(deactivateSession: Bool = true) {
        audioEngine.inputNode.removeTap(onBus: 0)

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioLock.withLock {
            recognitionRequest?.endAudio()
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if deactivateSession {
            Task.detached(priority: .background) {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}

final class SpeechRecognitionTaskDelegateProxy: NSObject, SFSpeechRecognitionTaskDelegate {
    private let onHypothesize: @Sendable(String) -> Void
    private let onFinish: @Sendable(String) -> Void
    private let onComplete: @Sendable(Error?) -> Void

    init(
        onHypothesize: @escaping @Sendable(String) -> Void,
        onFinish: @escaping @Sendable(String) -> Void,
        onComplete: @escaping @Sendable(Error?) -> Void
    ) {
        self.onHypothesize = onHypothesize
        self.onFinish = onFinish
        self.onComplete = onComplete
        super.init()
    }

    func speechRecognitionTask(
        _: SFSpeechRecognitionTask,
        didHypothesizeTranscription transcription: SFTranscription
    ) {
        onHypothesize(transcription.formattedString)
    }

    func speechRecognitionTask(
        _: SFSpeechRecognitionTask,
        didFinishRecognition recognitionResult: SFSpeechRecognitionResult
    ) {
        onFinish(recognitionResult.bestTranscription.formattedString)
    }

    func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask,
        didFinishSuccessfully _: Bool
    ) {
        onComplete(task.error)
    }
}
