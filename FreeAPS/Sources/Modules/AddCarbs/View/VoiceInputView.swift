import SwiftUI

struct VoiceInputView: View {
    @StateObject private var speechService = SpeechRecognitionService()
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @State private var pulseAnimation = false
    @State private var permissionGranted = false
    @State private var hasStartedListening = false
    @State private var hasCompleted = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Status header
                statusHeader

                // Microphone visual
                microphoneVisual

                // Transcript display
                transcriptDisplay

                Spacer()

                // Bottom buttons
                bottomButtons
            }
            .padding()
        }
        .task {
            await requestPermissionsAndStart()
        }
        .onChange(of: speechService.state) { newState in
            if case let .finished(text) = newState {
                guard !hasCompleted else { return }
                hasCompleted = true
                let impactLight = UIImpactFeedbackGenerator(style: .light)
                impactLight.impactOccurred()
                onComplete(text)
            }
        }
        .onDisappear {
            speechService.cancel()
        }
    }

    // MARK: - Subviews

    private var statusHeader: some View {
        Group {
            switch speechService.state {
            case .idle,
                 .requesting:
                Text("Preparing…")
                    .font(.title3)
                    .foregroundColor(.secondary)
            case .listening:
                Text("Listening…")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.indigo)
            case .processing:
                Text("Processing…")
                    .font(.title3)
                    .foregroundColor(.secondary)
            case .finished:
                Text("Done!")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.green)
            case let .error(message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var microphoneVisual: some View {
        ZStack {
            // Outer pulse ring
            if speechService.state == .listening {
                Circle()
                    .stroke(Color.indigo.opacity(0.3), lineWidth: 3)
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )

                Circle()
                    .stroke(Color.indigo.opacity(0.2), lineWidth: 2)
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulseAnimation ? 1.6 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.5)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.3),
                        value: pulseAnimation
                    )
            }

            // Main circle
            Circle()
                .fill(
                    speechService.state == .listening
                        ? Color.indigo
                        : Color(.systemGray4)
                )
                .frame(width: 100, height: 100)
                .shadow(
                    color: speechService.state == .listening ? .indigo.opacity(0.4) : .clear,
                    radius: 15,
                    y: 5
                )

            // Mic icon
            Image(systemName: speechService.state == .listening ? "mic.fill" : "mic")
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(.white)
        }
        .onAppear {
            pulseAnimation = true
        }
        .onTapGesture {
            handleMicTap()
        }
    }

    private var transcriptDisplay: some View {
        VStack(spacing: 12) {
            if !speechService.transcript.isEmpty {
                Text(speechService.transcript)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeInOut(duration: 0.2), value: speechService.transcript)
            } else if speechService.state == .listening {
                Text("Describe what you ate…")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.6))
                    .italic()
            }
        }
        .frame(minHeight: 60)
    }

    private var bottomButtons: some View {
        HStack(spacing: 20) {
            // Cancel button
            Button {
                speechService.cancel()
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.systemGray5))
                    )
            }

            // Retry / Done button
            if case .error = speechService.state {
                Button {
                    speechService.startListening()
                } label: {
                    Text("Retry")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.indigo)
                        )
                }
            } else if speechService.state == .listening, !speechService.transcript.isEmpty {
                Button {
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    let text = speechService.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    speechService.stopListening()
                    onComplete(text)
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.indigo)
                        )
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: - Actions

    private func requestPermissionsAndStart() async {
        let granted = await speechService.requestPermissions()
        permissionGranted = granted
        if granted {
            speechService.startListening()
            hasStartedListening = true
        }
    }

    private func handleMicTap() {
        switch speechService.state {
        case .listening:
            if speechService.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                guard !hasCompleted else { return }
                hasCompleted = true
                let text = speechService.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                speechService.stopListening()
                onComplete(text)
            }
        case .error,
             .idle:
            speechService.startListening()
        default:
            break
        }
    }
}
