import PhotosUI
import SwiftUI
import UIKit

struct AIProgressView: View {
    let analysisRequest: AnalysisRequest
    let onFoodAnalyzed: (FoodAnalysisResult, AnalysisRequest) -> Void
    let onCancel: () -> Void

    @State private var isAnalyzing: Bool = false

    @State private var analysisError: String?
    @State private var showingErrorAlert = false
    @State private var telemetryLogs: [String] = []
    @State private var selectedPhotoItem: PhotosPickerItem?

    @State private var searchTask: Task<Void, Never>? = nil
    @State private var analysisStart: Date? = nil
    @State private var analysisEnd: Date? = nil
    @State private var analysisEta: TimeInterval?
    @State private var analysisModel: String?
    @State private var latestTelemetry: String?

    var body: some View {
        let sideInset: CGFloat = 20
        let isAnalysisComplete = analysisEnd != nil

        return ZStack {
            // Main content area - fills entire space
            Group {
                switch analysisRequest {
                case let .image(image):
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(isAnalysisComplete ? 0.1 : 0.3),
                                        Color.blue.opacity(isAnalysisComplete ? 0.08 : 0.2),
                                        Color.purple.opacity(isAnalysisComplete ? 0.08 : 0.2),
                                        Color.cyan.opacity(isAnalysisComplete ? 0.1 : 0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.cyan.opacity(isAnalysisComplete ? 0.05 : 0.15), radius: 12, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
                    .padding(.horizontal, sideInset)
                    .padding(.top, 60) // Space for badge
                    .padding(.bottom, 80) // Space for progress bar

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
                            Text("Searching for")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text(query)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.cyan.opacity(isAnalysisComplete ? 0.1 : 0.3),
                                        Color.blue.opacity(isAnalysisComplete ? 0.08 : 0.2),
                                        Color.purple.opacity(isAnalysisComplete ? 0.08 : 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.cyan.opacity(isAnalysisComplete ? 0.05 : 0.15), radius: 12, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
                    .padding(.horizontal, sideInset)
                    .padding(.top, 60) // Space for badge
                    .padding(.bottom, 80) // Space for progress bar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Badge overlay - top
            VStack {
                HStack {
                    Spacer()
                    if let model = analysisModel {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(model)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .fontDesign(.rounded)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, sideInset)
                .padding(.bottom, 16)
                
                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: analysisModel)
            
            // Progress bar overlay - bottom
            VStack {
                Spacer()
                
                AnalyzingPill(
                    title: NSLocalizedString("Analyzing food with AI…", comment: ""),
                    startDate: analysisStart,
                    eta: analysisEta,
                    endDate: analysisEnd
                ) {
                    searchTask?.cancel()
                    searchTask = nil
                    analysisStart = nil
                    analysisEnd = nil
                    isAnalyzing = false
                    onCancel()
                }
                .padding(.horizontal, sideInset)
                .padding(.vertical, 16)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !isAnalyzing, analysisError == nil {
                    analyzeImage()
                }
            }
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
        .navigationBarHidden(true)
        .alert("Analysis Error", isPresented: $showingErrorAlert) {
            // Credit/quota exhaustion errors - provide direct guidance
            if analysisError?.contains("credits exhausted") == true || analysisError?.contains("quota exceeded") == true {
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                }
            }
            // Rate limit errors - suggest waiting
            else if analysisError?.contains("rate limit") == true {
                Button("Wait and Retry") {
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        analyzeImage()
                    }
                }
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                    onCancel()
                }
            }
            // General errors - provide standard options
            else {
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                    onCancel()
                }
            }
        } message: {
            if analysisError?.contains("credits exhausted") == true {
                Text("Your AI provider has run out of credits. Please check your account billing or try a different provider.")
            } else if analysisError?.contains("quota exceeded") == true {
                Text("Your AI provider quota has been exceeded. Please check your usage limits or try a different provider.")
            } else if analysisError?.contains("rate limit") == true {
                Text("Too many requests sent to your AI provider. Please wait a moment before trying again.")
            } else {
                Text(analysisError ?? "Unknown error occurred")
            }
        }
    }

    private func analyzeImage() {
        // Check if AI service is configured
        let aiService = ConfigurableAIService.shared

        switch analysisRequest {
        case .image:
            guard aiService.isImageAnalysisConfigured else {
                analysisError = "AI service not configured. Please check settings."
                showingErrorAlert = true
                return
            }
        case .query:
            guard aiService.isTextSearchConfigured else {
                analysisError = "AI service not configured. Please check settings."
                showingErrorAlert = true
                return
            }
        }

        isAnalyzing = true
        analysisError = nil
        telemetryLogs = []
        analysisStart = Date()
        analysisEnd = nil
        analysisEta = nil
        analysisModel = nil
        latestTelemetry = nil

        searchTask?.cancel()
        searchTask = Task {
            do {
                switch analysisRequest {
                case let .image(image):
                    let result = try await aiService.analyzeFoodImage(image) { telemetryMessage in
                        Task { @MainActor in
                            if telemetryMessage.hasPrefix("ETA: ") {
                                let etaString = telemetryMessage.dropFirst(5)
                                if let etaValue = Double(etaString.trimmingCharacters(in: .whitespaces)) {
                                    analysisEta = etaValue * 1.2
                                }
                            } else if telemetryMessage.hasPrefix("MODEL: ") {
                                analysisModel = String(telemetryMessage.dropFirst("MODEL: ".count))
                            } else {
                                latestTelemetry = telemetryMessage
                                addTelemetryLog(telemetryMessage)
                            }
                        }
                    }
                    await MainActor.run {
                        addTelemetryLog("✅ Analysis complete!")
                        analysisEnd = Date.now
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isAnalyzing = false
                            onFoodAnalyzed(result, analysisRequest)
                        }
                    }
                case let .query(query):
                    let result = try await aiService.analyzeFoodQuery(query) { telemetryMessage in
                        Task { @MainActor in
                            if telemetryMessage.hasPrefix("ETA: ") {
                                let etaString = telemetryMessage.dropFirst("ETA: ".count)
                                if let etaValue = Double(etaString.trimmingCharacters(in: .whitespaces)) {
                                    analysisEta = etaValue * 1.2
                                }
                            } else if telemetryMessage.hasPrefix("MODEL: ") {
                                analysisModel = String(telemetryMessage.dropFirst("MODEL: ".count))
                            } else {
                                latestTelemetry = telemetryMessage
                                addTelemetryLog(telemetryMessage)
                            }
                        }
                    }
                    await MainActor.run {
                        addTelemetryLog("✅ Analysis complete!")
                        analysisEnd = Date.now
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isAnalyzing = false
                            onFoodAnalyzed(result, analysisRequest)
                        }
                    }
                }

            } catch {
                await MainActor.run {
                    addTelemetryLog("⚠️ Connection interrupted")
                }
                try? await Task.sleep(nanoseconds: 300_000_000)

                await MainActor.run {
                    addTelemetryLog("❌ Analysis failed")

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isAnalyzing = false
                        analysisStart = nil
                        analysisEnd = nil
                        analysisError = error.localizedDescription
                        showingErrorAlert = true
                    }
                }
            }
        }
    }

    private func addTelemetryLog(_ message: String) {
        telemetryLogs.append(NSLocalizedString(message, comment: "Telemetry log"))
        if telemetryLogs.count > 10 {
            telemetryLogs.removeFirst()
        }
    }
}

struct TelemetryWindow: View {
    let logs: [String]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.green)
                    .font(.caption2)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                Text("Analysis Status")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()
                .opacity(0.3)

            // Scrolling logs
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .opacity(0.6)

                                Text(NSLocalizedString(log, comment: "Log"))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .id(index)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        Color.clear.frame(height: 12)
                    }
                    .padding(.top, 8)
                    .onAppear {
                        if !logs.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: logs.count) {
                        if !logs.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(height: 280)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.15),
            radius: 20,
            x: 0,
            y: 10
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.2 : 0.4),
                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
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
            // Running wave (outer halo) – larger around the hotspot
//            .overlay(
//                Capsule()
//                    .strokeBorder(
//                        AngularGradient(
//                            gradient: Gradient(colors: waveColors),
//                            center: .center,
//                            angle: .degrees(rotation)
//                        ),
//                        lineWidth: waveOuterLineWidth
//                    )
//                    .blur(radius: waveOuterBlur)
//                    .opacity(colorScheme == .dark ? waveOuterOpacityDark : waveOuterOpacityLight)
//                    .blendMode(.plusLighter)
//            )
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
                    if !progressState.isFinished {
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
            }
            .onChange(of: startDate) { _, newStartDate in
                // Reset progress when a new analysis starts
                if newStartDate != nil {
                    progress = 0.0
                    progressState = ProgressState(eta: eta, isFinished: false, isOvertime: false)
                }
            }
            .onChange(of: eta) { _, newEta in
                progressState = ProgressState(eta: newEta, isFinished: endDate != nil, isOvertime: progressState.isOvertime)
            }
            .onChange(of: endDate) { _, _ in
                progressState = ProgressState(eta: eta, isFinished: endDate != nil, isOvertime: progressState.isOvertime)
            }
            .onChange(of: progressState) { _, state in
                if state.isFinished {
                    // Finished: reset animation ID to cancel any in-flight animation, then immediately set to 100%
                    progressAnimationID = UUID()
                    progress = 1.0
                } else if state.isOvertime {
                    // Overtime: reset animation ID and immediately set to 100%
                    progressAnimationID = UUID()
                    progress = 1.0
                } else if let eta = state.eta {
                    // Normal: animate to 100% over ETA duration
                    withAnimation(.easeOut(duration: eta)) {
                        progress = 1.0
                    }
                }
            }
    }
}
