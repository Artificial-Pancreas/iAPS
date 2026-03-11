import PhotosUI
import SwiftUI
import UIKit

struct AIProgressView: View {
    @ObservedObject var state: FoodSearchStateModel

    let onCancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .background(.regularMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    searchTypeView
                        .padding(.horizontal, 20)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: Swift.max(geometry.size.height - geometry.safeAreaInsets.bottom - 140, 20)
                        )

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, 140)

                VStack(spacing: 0) {
                    if state.analysisError == nil {
                        HStack {
                            if let model = state.analysisModel {
                                Text(model)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state.analysisModel)

                        AnalyzingPill(
                            title: NSLocalizedString("Analyzing food with AI…", comment: ""),
                            startDate: state.analysisStart,
                            eta: state.analysisEta,
                            endDate: state.analysisEnd,
                            onCancel: {
                                onCancel()
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 120))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.analysisError)
            }
        }
        .ignoresSafeArea()
    }

    private var searchTypeView: some View {
        let isAnalysisComplete = state.analysisEnd != nil

        return VStack(spacing: 12) {
            switch state.aiAnalysisRequest {
            case let .image(image, _):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

            case let .query(query):
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(0.2),
                                        Color.blue.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.pulse, options: .repeating, value: !isAnalysisComplete)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(query)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }

                    Spacer()
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            case nil:
                EmptyView()
            }

            if let error = state.analysisError {
                InlineErrorBanner(
                    error: error,
                    onRetry: {
                        state.retryAIAnalysis()
                    },
                    onCancel: {
                        onCancel()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.analysisError)
    }
}

struct AnalyzingPill: View {
    var title: String
    var startDate: Date? = nil
    var eta: TimeInterval? = nil
    var endDate: Date? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var rotation: Double = 0
    @State private var shimmerPhase: CGFloat = -140
    @State private var progress: CGFloat = 0.0
    @State private var progressAnimationID = UUID()

    // Combined state to track all relevant changes
    @State private var progressState = ProgressState()

    private struct ProgressState: Equatable {
        var eta: TimeInterval? = nil
        var isFinished: Bool = false
        var isOvertime: Bool = false
    }

    // Helper function to format elapsed time
    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    var body: some View {
        // Local constants for palette and sizing
        let baseColors: [Color] = [
            Color.gray.opacity(0.22), Color.gray.opacity(0.22),
            Color.teal.opacity(0.45), Color.yellow.opacity(0.45), Color.red.opacity(0.45), Color.purple.opacity(0.45),
            Color.gray.opacity(0.22), Color.gray.opacity(0.22)
        ]
        let waveColors: [Color] = [
            .clear, .clear,
            Color.teal.opacity(0.7), Color.yellow.opacity(0.7), Color.red.opacity(0.7), Color.purple.opacity(0.7),
            .clear, .clear
        ]

        let innerFillBlur: CGFloat = 22
        let innerFillOpacityDark: CGFloat = 0.15
        let innerFillOpacityLight: CGFloat = 0.10

        let outerHaloLineWidth: CGFloat = 2
        let outerHaloBlur: CGFloat = 6
        let outerHaloOpacityDark: CGFloat = 0.32
        let outerHaloOpacityLight: CGFloat = 0.18

        let waveInnerBlur: CGFloat = 28
        let waveInnerOpacityDark: CGFloat = 0.45
        let waveInnerOpacityLight: CGFloat = 0.30

        let waveOuterLineWidth: CGFloat = 10
        let waveOuterBlur: CGFloat = 20
        let waveOuterOpacityDark: CGFloat = 0.50
        let waveOuterOpacityLight: CGFloat = 0.35

        let borderLineWidth: CGFloat = 0.6
        let borderBlur: CGFloat = 0.8
        let borderOpacity: CGFloat = 0.4

        // Determine the display text based on state
        let displayText: String = {
            if let startDate = self.startDate, let endDate = self.endDate {
                let elapsed = endDate.timeIntervalSince(startDate)
                let formattedElapsedTime = formatElapsedTime(elapsed)
                return "\(NSLocalizedString("Finished in", comment: "AI analysis finished in...")) \(formattedElapsedTime)"
            } else if progressState.isOvertime {
                return NSLocalizedString("AI is still thinking…", comment: "AI analysis taking longer than expected")
            } else {
                return title
            }
        }()

        let content = HStack(spacing: 10) {
            Text(displayText)
                .font(.footnote)
                .foregroundStyle(.primary)
                .opacity(progressState.isFinished ? 0.9 : 0.7)
                .overlay {
                    if !progressState.isFinished {
                        Text(displayText)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .black.opacity(0.0), location: 0.0),
                                        .init(color: .white, location: 0.5),
                                        .init(color: .black.opacity(0.0), location: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .offset(x: shimmerPhase)
                            )
                    }
                }
            Spacer(minLength: 8)
            if let startDate = startDate {
                if endDate == nil {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        let elapsed = context.date.timeIntervalSince(startDate)

                        // Check if we've exceeded the ETA
                        if let eta = eta, elapsed > eta, !progressState.isOvertime {
                            DispatchQueue.main.async {
                                progressState = ProgressState(
                                    eta: progressState.eta,
                                    isFinished: progressState.isFinished,
                                    isOvertime: true
                                )
                            }
                        }

                        let displayTime: String = {
                            if progressState.isOvertime {
                                return formatElapsedTime(elapsed)
                            } else if let eta = eta {
                                return "\(formatElapsedTime(elapsed)) / \(formatElapsedTime(eta))"
                            } else {
                                return formatElapsedTime(elapsed)
                            }
                        }()

                        return Text(displayTime)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.primary)
                            .opacity(0.9)
                            .padding(.trailing, 6)
                    }
                }
            }

            if let onCancel {
                Button("Cancel", action: onCancel)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .backgroundStyle(.ultraThinMaterial)
                    .buttonStyle(.bordered)
                    .padding(.horizontal, -6)
                    .padding(.vertical, -4)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Cancel")
                    .opacity(endDate == nil ? 1 : 0)
                    .disabled(endDate != nil)
            }
        }

        return content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            // Progress bar underneath the inner glow
            .background(
                GeometryReader { geometry in
                    let progressColor = progressState.isFinished ? Color.green : Color.cyan
                    let progressWidth = geometry.size.width * progress

                    Capsule()
                        .fill(progressColor.opacity(0.9))
                        .frame(width: progressWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(progressAnimationID)
                }
                .mask(Capsule())
            )
            // Inner fill glow covering the whole capsule (subtle, neutral+color)
            .background(
                AngularGradient(
                    gradient: Gradient(colors: baseColors),
                    center: .center,
                    angle: .degrees(rotation)
                )
                .blur(radius: innerFillBlur)
                .opacity(colorScheme == .dark ? innerFillOpacityDark : innerFillOpacityLight)
                .blendMode(.plusLighter)
                .mask(Capsule())
            )
            // Outer halo (soft, subtle)
            .background(
                Capsule()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: baseColors),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: outerHaloLineWidth
                    )
                    .blur(radius: outerHaloBlur)
                    .opacity(colorScheme == .dark ? outerHaloOpacityDark : outerHaloOpacityLight)
                    .blendMode(.plusLighter)
            )
            // Running wave (inner fill) amplifies the glow and spills inside
            .background(
                AngularGradient(
                    gradient: Gradient(colors: waveColors),
                    center: .center,
                    angle: .degrees(rotation)
                )
                .blur(radius: waveInnerBlur)
                .opacity(colorScheme == .dark ? waveInnerOpacityDark : waveInnerOpacityLight)
                .blendMode(.plusLighter)
                .mask(Capsule())
            )
            // Subtle border that blends with the glow
            .overlay(
                Capsule()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: baseColors),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: borderLineWidth
                    )
                    .blur(radius: borderBlur)
                    .opacity(borderOpacity)
                    .blendMode(.plusLighter)
            )
            // Traveling spotlight using trim with wrap-around handling (timeline-driven)
            .overlay(
                Group {
                    if !progressState.isFinished, UserDefaults.standard.aiProgressAnimation {
                        TimelineView(.animation) { context in
                            let duration: TimeInterval = 5 // seconds per full revolution
                            let t = context.date.timeIntervalSinceReferenceDate
                            let phase = t.truncatingRemainder(dividingBy: duration) / duration
                            let seg: CGFloat = 0.05
                            let start = CGFloat(phase)
                            let end = start + seg

                            ZStack {
                                // Head segment (start ..< min(end, 1))
                                Capsule()
                                    .inset(by: 1.5)
                                    .trim(from: start, to: min(end, 1))
                                    .stroke(
                                        Color.white,
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                    )
                                    .blur(radius: 1)
                                    .opacity(colorScheme == .dark ? 0.2 : 0.2)
                                    .blendMode(.plusLighter)
                                    .allowsHitTesting(false)

                                Capsule()
                                    .inset(by: 1.5)
                                    .trim(from: start, to: min(end, 1))
                                    .stroke(
                                        Color.white,
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .blur(radius: 4)
                                    .opacity(colorScheme == .dark ? 0.2 : 0.2)
                                    .blendMode(.plusLighter)
                                    .allowsHitTesting(false)

                                // Tail segment (wraps from 0 when end > 1)
                                if end > 1 {
                                    Capsule()
                                        .inset(by: 1.5)
                                        .trim(from: 0, to: end - 1)
                                        .stroke(
                                            Color.white,
                                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                        )
                                        .blur(radius: 1)
                                        .opacity(colorScheme == .dark ? 0.2 : 0.2)
                                        .blendMode(.plusLighter)
                                        .allowsHitTesting(false)

                                    Capsule()
                                        .inset(by: 1.5)
                                        .trim(from: 0, to: end - 1)
                                        .stroke(
                                            Color.white,
                                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                        )
                                        .blur(radius: 4)
                                        .opacity(colorScheme == .dark ? 0.2 : 0.2)
                                        .blendMode(.plusLighter)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                }
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.1), radius: 10, x: 0, y: 5)
            .onAppear {
                // Delay animations slightly to allow navigation to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }

                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        shimmerPhase = 140
                    }
                }

                // Initialize progress state
                progressState = ProgressState(eta: eta, isFinished: endDate != nil, isOvertime: false)
            }
            .onChange(of: eta) { _, newEta in
                // Update progress state with new ETA
                progressState = ProgressState(eta: newEta, isFinished: endDate != nil, isOvertime: progressState.isOvertime)
            }
            .onChange(of: endDate) { _, newEndDate in
                // Update progress state when analysis finishes
                progressState = ProgressState(eta: eta, isFinished: newEndDate != nil, isOvertime: progressState.isOvertime)
            }
            .onChange(of: progressState) { oldState, newState in
                if newState.isFinished {
                    // Finished: cancel any in-flight animation and immediately set to 100%
                    progressAnimationID = UUID()
                    progress = 1.0
                } else if newState.isOvertime {
                    // Overtime: cancel any in-flight animation and immediately set to 100%
                    progressAnimationID = UUID()
                    progress = 1.0
                } else if let newEta = newState.eta, oldState.eta != newEta, !newState.isFinished, !newState.isOvertime {
                    // ETA became available or changed: start/restart progress animation
                    progressAnimationID = UUID() // Cancel any existing animation
                    progress = 0.0
                    withAnimation(.easeOut(duration: newEta)) {
                        progress = 1.0
                    }
                }
            }
    }
}

struct InlineErrorBanner: View {
    let error: String
    var onRetry: (() -> Void)? = nil
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.2),
                                    Color.orange.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Failed")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Text("Retry")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.3),
                            Color.orange.opacity(0.2),
                            Color.red.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.red.opacity(0.15), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}
