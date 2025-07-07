// HomeRootView Design by Rig22
import Charts
import Combine
import CoreData
import DanaKit
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State var isStatusPopupPresented = false
        @State var showCancelAlert = false
        @State var showCancelTTAlert = false
        @State var triggerUpdate = false
        @State var scrollOffset = CGFloat.zero
        @State var display = false
        @State var displayGlucose = false
        @State var showBolusActiveAlert = false
        @State var displayAutoHistory = false
        @State var displayDynamicHistory = false

        @Namespace var scrollSpace

        let scrollAmount: CGFloat = 290
        let buttonFont = Font.custom("TimeButtonFont", size: 14)

        @Environment(\.managedObjectContext) var moc
        @Environment(\.sizeCategory) private var fontSize
        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Override.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var fetchedPercent: FetchedResults<Override>

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "" as String
            )
        ) var fetchedProfiles: FetchedResults<OverridePresets>

        @FetchRequest(
            entity: TempTargets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var sliderTTpresets: FetchedResults<TempTargets>

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var enactedSliderTT: FetchedResults<TempTargetsSlider>

        @FetchRequest(
            entity: InsulinConcentration.entity(),
            sortDescriptors: [NSSortDescriptor(
                key: "date",
                ascending: true
            )]
        ) var concentration: FetchedResults<InsulinConcentration>

        @FetchRequest(
            entity: Onboarding.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var onboarded: FetchedResults<Onboarding>

        @State private var progress: Double = 0.0

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var tempRatenumberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2 // Immer zwei Nachkommastellen anzeigen
            return formatter
        }

        private var insulinnumberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 0 // Keine unnötigen Nullen
            formatter.locale = Locale(identifier: "de_DE_POSIX")
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.data.units == .mmolL {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var fetchedTargetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.data.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var targetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var tirFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            return dateFormatter
        }

        private var reservoirFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var daysFormatter: DateComponentsFormatter {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day, .hour]
            formatter.unitsStyle = .abbreviated
            return formatter
        }

        private var remainingTimeFormatter: DateComponentsFormatter {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day, .hour]
            formatter.unitsStyle = .abbreviated
            return formatter
        }

        private var remainingTimeFormatterDays: DateComponentsFormatter {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day]
            formatter.unitsStyle = .short
            return formatter
        }

        var bolusProgressFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.minimumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.allowsFloats = true
            formatter.roundingIncrement = Double(state.settingsManager.preferences.bolusIncrement) as NSNumber
            return formatter
        }

        let percentageFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0 // Keine Nachkommastellen
            return formatter
        }()

        private var spriteScene: SKScene {
            let scene = SnowScene()
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            return scene
        }

        struct TimeEllipse: View {
            let characters: Int
            var button3D: Bool = false
            var button3DBackground: Bool = false
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector

            var body: some View {
                ZStack {
                    if button3D {
                        let glowColor1 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.9)

                        let glowColor2 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.4)

                        if button3DBackground {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.black.opacity(0.2))
                                .frame(width: CGFloat(characters * 7), height: 25)
                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                        }

                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        glowColor1.opacity(0.5),
                                        glowColor2.opacity(0.3),
                                        Color.clear,
                                        Color.black.opacity(0.3),
                                        Color.black.opacity(0.6)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom

                                ),
                                lineWidth: 1
                            )
                            .frame(width: CGFloat(characters * 7), height: 25)
                    } else {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.2))
                            .frame(width: CGFloat(characters * 7), height: 25)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white, lineWidth: 0)
                            )
                    }
                }
            }
        }

        struct TimeEllipseBig: View {
            let characters: Int
            var button3D: Bool = false
            var button3DBackground: Bool = false
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector

            var body: some View {
                ZStack {
                    if button3D {
                        let glowColor1 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.9)

                        let glowColor2 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.4)

                        if button3DBackground {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.2))
                                .frame(width: CGFloat(characters * 10), height: 25)
                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                        }

                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        glowColor1.opacity(1.0),
                                        glowColor2.opacity(0.8),
                                        Color.clear,
                                        Color.black.opacity(0.3),
                                        Color.black.opacity(0.6)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom

                                ),
                                lineWidth: 1
                            )
                            .frame(width: CGFloat(characters * 10), height: 26)
                    } else {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.2))
                            .frame(width: CGFloat(characters * 10), height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(Color.white, lineWidth: 0)
                            )
                    }
                }
            }
        }

        struct BatteryEllipse: View {
            var battery: Battery?
            var button3D: Bool
            var button3DBackground: Bool
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector
            @State private var isLowBatteryBlinking = false

            private var shouldBlink: Bool {
                guard let percent = battery?.percent else { return false }
                return percent <= 50
            }

            private var batteryColor: Color {
                guard let percent = battery?.percent else { return .gray }
                switch percent {
                case ...25: return .red
                case ...50: return .yellow
                default: return .green
                }
            }

            private var batterySymbol: String {
                guard let percent = battery?.percent else { return "battery.0" }
                switch percent {
                case 81 ... 100: return "battery.100"
                case 61 ... 80: return "battery.75"
                case 41 ... 60: return "battery.50"
                case 21 ... 40: return "battery.25"
                default: return "battery.0"
                }
            }

            private var percentageText: String {
                if let percent = battery?.percent {
                    return "\(percent)%"
                } else {
                    return "--"
                }
            }

            var body: some View {
                ZStack {
                    if button3D {
                        let glowColor1 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.9)

                        let glowColor2 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.4)

                        if button3DBackground {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.black.opacity(0.2))
                                .frame(width: 74, height: 25) // Feste Breite für Batterie
                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                        }

                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        glowColor1.opacity(0.9),
                                        glowColor2.opacity(0.6),
                                        Color.clear,
                                        Color.black.opacity(0.3),
                                        Color.black.opacity(0.6)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .frame(width: 74, height: 25)
                    } else {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.2))
                            .frame(width: 74, height: 25)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: batterySymbol)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(batteryColor)
                            .opacity(shouldBlink ? (isLowBatteryBlinking ? 0.5 : 1) : 1)

                        Text(percentageText)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                }
                .onAppear { startBlinkAnimationIfNeeded() }
                .onChange(of: battery?.percent) {
                    startBlinkAnimationIfNeeded()
                } }

            private func startBlinkAnimationIfNeeded() {
                isLowBatteryBlinking = false
                guard shouldBlink else { return }

                withAnimation(
                    Animation.easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) {
                    isLowBatteryBlinking = true
                }
            }
        }

        struct LightGlowOverlay: View {
            var body: some View {
                RadialGradient(gradient: Gradient(colors: [
                    Color.gray.opacity(0.7),
                    Color.clear
                ]), center: .top, startRadius: 50, endRadius: 200)
                    .ignoresSafeArea()
                    .offset(y: -50)
            }
        }

        struct LightGlowOverlay1: View {
            var body: some View {
                RadialGradient(gradient: Gradient(colors: [
                    Color.white.opacity(0.7),
                    Color.clear
                ]), center: .top, startRadius: 50, endRadius: 200)
                    .ignoresSafeArea()
                    .offset(y: -50)
            }
        }

        struct LightGlowOverlay2: View {
            var body: some View {
                RadialGradient(gradient: Gradient(colors: [
                    Color.loopYellow.opacity(0.7),
                    Color.clear
                ]), center: .top, startRadius: 50, endRadius: 200)
                    .ignoresSafeArea()
                    .offset(y: -50)
            }
        }

        struct LightGlowOverlay3: View {
            var body: some View {
                RadialGradient(gradient: Gradient(colors: [
                    Color.orange.opacity(0.7),
                    Color.clear
                ]), center: .top, startRadius: 50, endRadius: 200)
                    .ignoresSafeArea()
                    .offset(y: -50)
            }
        }

        struct LightGlowOverlay4: View {
            var body: some View {
                RadialGradient(gradient: Gradient(colors: [
                    Color.red.opacity(0.7),
                    Color.clear
                ]), center: .top, startRadius: 50, endRadius: 200)
                    .ignoresSafeArea()
                    .offset(y: -50)
            }
        }

        struct LightGlowOverlay5: View {
            var body: some View {
                RadialGradient(gradient: Gradient(colors: [
                    Color.NorthernLights.opacity(0.7),
                    Color.clear
                ]), center: .top, startRadius: 50, endRadius: 200)
                    .ignoresSafeArea()
                    .offset(y: -50)
            }
        }

        var pumpView: some View {
            PumpView(
                reservoir: $state.reservoir,
                battery: $state.battery,
                name: $state.pumpName,
                expiresAtDate: $state.pumpExpiresAtDate,
                timerDate: $state.data.timerDate, timeZone: $state.timeZone,
                state: state
            )
            .onTapGesture {
                if state.pumpDisplayState != nil {
                    state.setupPump = true
                }
            }
            .offset(y: 1)
        }

        var glucoseView: some View {
            let doubleBolusProgress = Binding<Double?> {
                state.bolusProgress.map { Double(truncating: $0 as NSNumber) }
            } set: { newValue in
                if let newDecimalValue = newValue.map({ Decimal($0) }) {
                    state.bolusProgress = newDecimalValue
                }
            }

            return ZStack(alignment: .center) {
                let incidenceOfLight = state.incidenceOfLight
                let lightGlowOverlaySelector = LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                    .atriumview

                if state.button3D {
                    let glowColor1 = incidenceOfLight
                        ? lightGlowOverlaySelector.highlightColor
                        : Color.white.opacity(0.9)

                    let glowColor2 = incidenceOfLight
                        ? lightGlowOverlaySelector.highlightColor
                        : Color.white.opacity(0.4)

                    if state.button3DBackground {
                        Circle()
                            .fill(Color.black.opacity(0.2))
                            .frame(width: 110, height: 110)
                            .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                    }

                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    glowColor1.opacity(0.9),
                                    glowColor2.opacity(0.6),
                                    Color.clear,
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.6)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 110, height: 110)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 110, height: 110)
                }
                CurrentGlucoseView(
                    recentGlucose: $state.recentGlucose,
                    timerDate: $state.data.timerDate,
                    delta: $state.glucoseDelta,
                    units: $state.data.units,
                    alarm: $state.alarm,
                    lowGlucose: $state.data.lowGlucose,
                    highGlucose: $state.data.highGlucose,
                    bolusProgress: doubleBolusProgress,
                    displayDelta: $state.displayDelta,
                    alwaysUseColors: $state.alwaysUseColors,
                    scrolling: $displayGlucose,
                    displayExpiration: $state.displayExpiration, cgm: $state.cgm, sensordays: $state.sensorDays
                )
                .zIndex(1)
                .onTapGesture {
                    if state.alarm == nil {
                        state.openCGM()
                    } else {
                        state.showModal(for: .snooze)
                    }
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    if state.alarm == nil {
                        state.showModal(for: .snooze)
                    } else {
                        state.openCGM()
                    }
                }
            }
        }

        private func startProgress() {
            Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
                withAnimation(Animation.linear(duration: 0.02)) {
                    progress += 0.01
                }
                if progress >= 1.0 {
                    timer.invalidate()
                }
            }
        }

        // Progressbar by Rig22
        public struct CircularProgressViewStyle: ProgressViewStyle {
            public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
                let progress = CGFloat(configuration.fractionCompleted ?? 0)

                ZStack {
                    Circle()
                        .trim(from: 0.0, to: progress)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.5)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(Angle(degrees: 270))
                        .animation(.linear(duration: 0.25), value: progress)
                }
                .frame(width: 110, height: 110)
            }
        }

        @StateObject private var bolusPieSegmentViewModel2 = PieSegmentViewModel()

        @ViewBuilder private func bolusProgressView() -> some View {
            if let progress = state.bolusProgress, let amount = state.bolusAmount {
                let fillFraction = max(min(CGFloat(progress), 1.0), 0.0)
                let bolused = bolusProgressFormatter.string(from: (amount * progress) as NSNumber) ?? ""

                ZStack(alignment: .center) {
                    BigFillablePieSegment(
                        pieSegmentViewModel: bolusPieSegmentViewModel2,
                        fillFraction: fillFraction,
                        backgroundColor: backgroundColor,
                        color: .blue,
                        animateProgress: true,
                        button3D: state.button3D,
                        button3DBackground: state.button3DBackground,
                        incidenceOfLight: state.incidenceOfLight,
                        lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                            .atriumview
                    )
                    .frame(width: 110, height: 110)

                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 110, height: 110)

                    Circle()
                        .fill(backgroundColor.opacity(1.0))
                        .frame(width: 80, height: 80)

                    Circle()
                        .fill(Color.clear)
                        .frame(width: 25, height: 25)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .onTapGesture { state.cancelBolus() }

                    Text(
                        bolused + " " + NSLocalizedString("of", comment: "") + " " +
                            amount.formatted(.number.precision(.fractionLength(2))) +
                            NSLocalizedString(" U", comment: " ")
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white)
                    .offset(y: -80)
                }
                .frame(width: 110, height: 110)
            }
        }

        // Pie Animation Anfang

        struct PieSliceView: Shape {
            var startAngle: Angle
            var endAngle: Angle
            var animatableData: AnimatablePair<Double, Double> {
                get {
                    AnimatablePair(startAngle.degrees, endAngle.degrees)
                }
                set {
                    startAngle = Angle(degrees: newValue.first)
                    endAngle = Angle(degrees: newValue.second)
                }
            }

            func path(in rect: CGRect) -> Path {
                var path = Path()
                let center = CGPoint(x: rect.midX, y: rect.midY)
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: rect.width / 2,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
                path.closeSubpath()
                return path
            }
        }

        // Fillable PieSegments Anfang
        class PieSegmentViewModel: ObservableObject {
            @Published var progress: Double = 0.0

            func updateProgress(to newValue: CGFloat, animate: Bool) {
                if animate {
                    withAnimation(.easeInOut(duration: 2.5)) {
                        self.progress = Double(newValue)
                    }
                } else {
                    progress = Double(newValue)
                }
            }
        }

        struct FillablePieSegment: View {
            @ObservedObject var pieSegmentViewModel: PieSegmentViewModel

            // var fillFraction: CGFloat
            var color: Color
            var backgroundColor: Color
            var displayText: String
            var symbolSize: CGFloat
            var symbol: String
            var animateProgress: Bool
            var button3D: Bool
            var button3DBackground: Bool
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector
            var fillFraction: CGFloat
            var symbolRotation: Double = 0
            var symbolBackgroundColor: Color = .clear

            let angularGradient = AngularGradient(
                gradient: Gradient(colors: [
                    Color.gray.opacity(0.3)
                ]),
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )

            var body: some View {
                VStack {
                    ZStack {
                        if button3D {
                            let glowColor1 = incidenceOfLight
                                ? lightGlowOverlaySelector.highlightColor
                                : Color.white.opacity(0.7)

                            let glowColor2 = incidenceOfLight
                                ? lightGlowOverlaySelector.highlightColor
                                : Color.white.opacity(0.4)

                            if button3DBackground {
                                Circle()
                                    .fill(Color.black.opacity(0.2))
                                    .frame(width: 50, height: 50)
                                    .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                            }

                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            glowColor1.opacity(0.7),
                                            glowColor2.opacity(0.3),
                                            Color.clear,
                                            Color.black.opacity(0.3),
                                            Color.black.opacity(0.6)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                                .frame(width: 50, height: 50)
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.2))
                                .frame(width: 50, height: 50)
                        }

                        PieSliceView(
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + Double(pieSegmentViewModel.progress * 360))
                        )
                        .fill(color)
                        .frame(width: 50, height: 50)
                        .opacity(0.5)

                        // Symbol-Hintergrund (NEU, 40x40)
                        if symbolBackgroundColor != .clear {
                            Circle()
                                .fill(symbolBackgroundColor)
                                .frame(width: 40, height: 40)
                        }

                        Image(systemName: symbol)
                            .resizable()
                            .scaledToFit()
                            .frame(width: symbolSize, height: symbolSize)
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(symbolRotation))
                    }

                    Text(displayText)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
                .offset(y: 10)
                .onAppear {
                    pieSegmentViewModel.updateProgress(to: fillFraction, animate: animateProgress)
                }
                .onChange(of: fillFraction) { _, newValue in
                    pieSegmentViewModel.updateProgress(to: newValue, animate: true)
                }
            }
        }

        struct BigFillablePieSegment: View {
            @ObservedObject var pieSegmentViewModel: PieSegmentViewModel

            var fillFraction: CGFloat
            var backgroundColor: Color?
            var color: Color
            var animateProgress: Bool
            var button3D: Bool
            var button3DBackground: Bool
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector

            var body: some View {
                ZStack {
                    if button3D {
                        let glowColor1 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.9)

                        let glowColor2 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.4)

                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        glowColor1.opacity(0.9),
                                        glowColor2.opacity(0.6),
                                        Color.clear,
                                        Color.black.opacity(0.3),
                                        Color.black.opacity(0.6)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    } else {}

                    PieSliceView(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + Double(pieSegmentViewModel.progress * 360))
                    )
                    .fill(color)
                    .frame(width: 110, height: 110)
                    .opacity(1.0)
                }
                .onAppear {
                    pieSegmentViewModel.updateProgress(to: fillFraction, animate: animateProgress)
                }
                .onChange(of: fillFraction) { _, newValue in
                    pieSegmentViewModel.updateProgress(to: newValue, animate: true)
                }
            }
        }

        // Fillable PieSegments Ende

        // HEADERVIEW Anfang

        private var stackedLeftTopView: some View {
            VStack(spacing: 25) {
                tempRateView
                carbsView
                insulinView
            }
        }

        private var stackedRightTopView: some View {
            VStack(spacing: 120) {
                eventualBGView
                loopView
                // pumpView
            }
        }

        // Temp Basal Anfang
        private var tempRateView: some View {
            ZStack {
                VStack {
                    HStack {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)

                        if let tempRate = state.tempRate {
                            let rateString = tempRatenumberFormatter.string(from: tempRate as NSNumber) ?? "0"
                            let manualBasalString = state.apsManager.isManualTempBasal
                                ? NSLocalizedString(" Manual", comment: "Manual Temp basal")
                                : ""

                            HStack(spacing: 0) {
                                Text(rateString)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)

                                Text("\u{00A0}U/hr") // Ein geschütztes Leerzeichen
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    +
                                    Text(manualBasalString)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        } else {
                            Text("---")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                    }
                    .font(.timeSettingFont)
                    .background(
                        TimeEllipseBig(
                            characters: 11,
                            button3D: state.button3D,
                            button3DBackground: state.button3DBackground,
                            incidenceOfLight: state.incidenceOfLight,
                            lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview
                        )
                    )
                }
            }
        }

        // Temp Basal Ende

        var batteryView: some View {
            BatteryEllipse(
                battery: state.battery,
                button3D: state.button3D,
                button3DBackground: state.button3DBackground,
                incidenceOfLight: state.incidenceOfLight,
                lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ?? .atriumview
            )
            .offset(y: 0)
        }

        // eventualBG Anfang

        private var eventualBGView: some View {
            ZStack {
                VStack {
                    HStack {
                        if let eventualBG = state.eventualBG {
                            HStack(spacing: 4) {
                                Text("⇢")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)

                                let eventualBGValue = state.data.units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)

                                if let formattedBG = fetchedTargetFormatter
                                    .string(from: eventualBGValue as NSNumber)
                                {
                                    Text(formattedBG)
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }

                                Text(state.data.units.rawValue)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .padding(.leading, -1)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Text("⇢")
                                    .font(.statusFont)
                                    .foregroundStyle(.white)

                                Text("---")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .font(.timeSettingFont)
                    .background(
                        TimeEllipseBig(
                            characters: 10,
                            button3D: state.button3D,
                            button3DBackground: state.button3DBackground,
                            incidenceOfLight: state.incidenceOfLight,
                            lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview
                        )
                    )
                }
            }
        }

        // eventualBG Ende

        @ViewBuilder private func glucoseAndLoopView() -> some View {
            VStack {
                glucoseView
                    .frame(width: 110, height: 110)
            }
        }

        @ViewBuilder private func headerView(_ geo: GeometryProxy) -> some View {
            let height: CGFloat = display ? 150 : 230
            LinearGradient(
                gradient: Gradient(colors: [.clear, .clear, .clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fontSize < .extraExtraLarge ? height + geo.safeAreaInsets.top : height + 10 + geo.safeAreaInsets.top)
            .overlay(alignment: .top) {
                lightGlowOverlayContent()

                // Horizontale Hauptcontainer
                HStack(spacing: 0) {
                    if !display {
                        stackedLeftTopView
                            .transition(.opacity)
                            .fixedSize()
                            .padding(.leading, 20)
                    }

                    VStack(spacing: 25) {
                        Group {
                            if display {
                                glucoseView
                            } else {
                                if let progress = state.bolusProgress, progress > 0 {
                                    bolusProgressView()
                                } else {
                                    glucoseAndLoopView()
                                }
                            }
                        }
                        if !display {
                            pumpView
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity) // Wichtig: Nimmt verfügbaren Platz ein

                    if !display {
                        stackedRightTopView
                            .transition(.opacity)
                            .fixedSize()
                            .padding(.trailing, 20)
                    }
                }
                .padding(.top, geo.safeAreaInsets.top + 20)
                .animation(.easeInOut(duration: 1.2), value: display)
            }
        }

        @ViewBuilder private func lightGlowOverlayContent() -> some View {
            if state.incidenceOfLight {
                if let selectedOverlay = LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) {
                    switch selectedOverlay {
                    case .atriumview: LightGlowOverlay()
                    case .atriumview1: LightGlowOverlay1()
                    case .atriumview2: LightGlowOverlay2()
                    case .atriumview3: LightGlowOverlay3()
                    case .atriumview4: LightGlowOverlay4()
                    case .atriumview5: LightGlowOverlay5()
                    }
                }
            }
        }

        // Head Ende

        // TopBar Anfang

        // CarbView Anfang
        @StateObject private var carbsPieSegmentViewModel = PieSegmentViewModel()

        var carbsView: some View {
            HStack {
                if let settings = state.settingsManager {
                    HStack {
                        ZStack {
                            let substance = Double(state.data.suggestion?.cob ?? 0)
                            let maxValue = max(Double(settings.preferences.maxCOB), 1)
                            let fraction = CGFloat(substance / maxValue)
                            let fill = max(min(fraction, 1.0), 0.0)

                            FillablePieSegment(
                                pieSegmentViewModel: carbsPieSegmentViewModel,
                                // fillFraction: fill,
                                // color: .white.opacity(0.5),
                                color: .orange,
                                backgroundColor: .clear,
                                displayText: "\(numberFormatter.string(from: (state.data.suggestion?.cob ?? 0) as NSNumber) ?? "0")g",
                                symbolSize: 20,
                                symbol: "fork.knife",
                                animateProgress: true,
                                button3D: state.button3D,
                                button3DBackground: state.button3DBackground,
                                incidenceOfLight: state.incidenceOfLight,
                                lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                    .atriumview,
                                fillFraction: fill,
                                symbolBackgroundColor: backgroundColor
                            )
                        }
                    }
                }
            }
        }

        // CarbView Ende

        // InsulinView Anfang

        @StateObject private var insulinPieSegmentViewModel = PieSegmentViewModel()

        var insulinView: some View {
            HStack {
                if let settings = state.settingsManager {
                    HStack {
                        ZStack {
                            let substance = Double(state.data.suggestion?.iob ?? 0)
                            let maxValue = max(Double(settings.preferences.maxIOB), 1)

                            let fraction = CGFloat(abs(substance) / maxValue)
                            let fill = min(fraction, 1.0)

                            let isNegative = substance < 0
                            // let pieColor: Color = isNegative ? .red : .white.opacity(0.5)
                            let pieColor: Color = isNegative ? .red : .blue

                            let _: Double = isNegative ? 90 : -90

                            FillablePieSegment(
                                pieSegmentViewModel:
                                insulinPieSegmentViewModel,
                                // fillFraction: fill,
                                color: pieColor,
                                backgroundColor: .clear,
                                displayText: "\(insulinnumberFormatter.string(from: (state.data.suggestion?.iob ?? 0) as NSNumber) ?? "0")U",
                                symbolSize: 20,
                                symbol: "syringe",
                                animateProgress: true,
                                button3D: state.button3D,
                                button3DBackground: state.button3DBackground,
                                incidenceOfLight: state.incidenceOfLight,
                                lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                    .atriumview,
                                fillFraction: fill,
                                symbolBackgroundColor: backgroundColor
                            )
                        }
                    }
                    .onTapGesture {
                        if state.pumpDisplayState != nil {
                            state.setupPump = true
                        }
                    }
                }
            }
        }

        // InsulinView Ende

        // LoopView

        var loopView: some View {
            ZStack {
                let incidenceOfLight = state.incidenceOfLight
                let lightGlowOverlaySelector = LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                    .atriumview

                if state.button3D {
                    let glowColor1 = incidenceOfLight
                        ? lightGlowOverlaySelector.highlightColor
                        : Color.white.opacity(0.9)

                    let glowColor2 = incidenceOfLight
                        ? lightGlowOverlaySelector.highlightColor
                        : Color.white.opacity(0.4)

                    if state.button3DBackground {
                        Circle()
                            .fill(Color.black.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                            .offset(y: -2.5)
                    }

                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    glowColor1,
                                    glowColor2.opacity(0.4),
                                    Color.clear,
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.6)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .frame(width: 50, height: 50)
                        .offset(y: -2.5)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .offset(y: -1.5)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 0)
                        )
                }

                LoopView(
                    suggestion: $state.data.suggestion,
                    enactedSuggestion: $state.enactedSuggestion,
                    closedLoop: $state.closedLoop,
                    timerDate: $state.data.timerDate,
                    isLooping: $state.isLooping,
                    lastLoopDate: $state.lastLoopDate,
                    manualTempBasal: $state.manualTempBasal,
                    backgroundColor: backgroundColor,
                )
                .onTapGesture {
                    state.isStatusPopupPresented.toggle()
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.runLoop()
                }
            }
        }

        // Top Bars

        @StateObject private var cannulaPieSegmentViewModel = PieSegmentViewModel()
        @StateObject private var reservoirPieSegmentViewModel = PieSegmentViewModel()
        @StateObject private var reservoirAgePieSegmentViewModel = PieSegmentViewModel()
        @StateObject private var connectionPieSegmentViewModel = PieSegmentViewModel()
        @StateObject private var insulinAgePieSegmentViewModel = PieSegmentViewModel()
        @StateObject private var batteryAgePieSegmentViewModel = PieSegmentViewModel()

        // Standard

        var danaBarStandard: some View {
            if state.danaBar {
                return AnyView(
                    VStack(spacing: 20) {
                        HStack(spacing: 20) {
                            HStack(spacing: 10) {
                                insulinAgeView
                            }
                            HStack(spacing: 10) {
                                cannulaAgeView
                            }
                            HStack(spacing: 10) {
                                sensorAgeDays
                            }
                        }
                    }
                )
            } else {
                return AnyView(EmptyView())
            }
        }

        // danaBarMax

        var danaBarMax: some View {
            if state.danaBar {
                return AnyView(
                    VStack(spacing: 20) {
                        HStack(spacing: 20) {
                            HStack(spacing: 10) {
                                insulinAgeView
                            }
                            HStack(spacing: 10) {
                                cannulaAgeView
                            }
                            HStack(spacing: 10) {
                                batteryAgeView
                            }
                            HStack(spacing: 10) {
                                sensorAgeDays
                            }
                            HStack(spacing: 10) {
                                BluetoothConnectionView
                            }
                        }
                    }
                )
            } else {
                return AnyView(EmptyView())
            }
        }

        // DanaBar Modules Start

        private var reservoirView: some View {
            Group {
                if let reservoir = state.reservoirLevel {
                    let maxValue = Decimal(300)
                    let reservoirDecimal = Decimal(reservoir)
                    let fractionDecimal = reservoirDecimal / maxValue
                    let fill = max(min(CGFloat(NSDecimalNumber(decimal: fractionDecimal).doubleValue), 1.0), 0.0)

                    let reservoirColor: Color = {
                        if reservoir < 20 {
                            return .red
                        } else if reservoir < 50 {
                            return .yellow
                        } else {
                            return .white.opacity(0.5)
                        }
                    }()

                    let displayText: String = {
                        if reservoir == 0 {
                            return "--"
                        } else {
                            let concentrationValue = Decimal(concentration.last?.concentration ?? 1.0)
                            let adjustedReservoir = reservoirDecimal * concentrationValue
                            return (reservoirFormatter.string(from: adjustedReservoir as NSNumber) ?? "") + "U"
                        }
                    }()

                    let shouldBlink = reservoir < 20

                    ZStack {
                        FillablePieSegment(
                            pieSegmentViewModel: reservoirPieSegmentViewModel,
                            // fillFraction: fill,
                            color: reservoirColor,
                            backgroundColor: .clear,
                            displayText: displayText,
                            symbolSize: 25,
                            symbol: "cross.vial.fill",
                            animateProgress: true,
                            button3D: state.button3D,
                            button3DBackground: state.button3DBackground,
                            incidenceOfLight: state.incidenceOfLight,
                            lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview,
                            fillFraction: fill
                        )
                        .frame(width: 60, height: 60)
                        .modifier(BlinkingModifier(shouldBlink: shouldBlink))
                    }
                }
            }
            .onTapGesture {
                if state.pumpDisplayState != nil {
                    state.setupPump = true
                }
            }
        }

        private var insulinAgeView: some View {
            Group {
                let insulinDisplayText: String = {
                    guard let insulinHours = state.insulinHours,
                          let insulinAgeOption = InsulinAgeOption(rawValue: state.insulinAgeOption)
                    else {
                        return "--"
                    }

                    let remainingHours = max(insulinAgeOption.maxInsulinAge - insulinHours, 0)
                    let totalRemainingMinutes = Int(remainingHours * 60)
                    let days = totalRemainingMinutes / (24 * 60)
                    let hours = (totalRemainingMinutes % (24 * 60)) / 60
                    let minutes = totalRemainingMinutes % 60

                    if days >= 1 {
                        return "\(days)d\(hours)h"
                    } else if hours >= 1 {
                        return "\(hours)h\(minutes)m"
                    } else {
                        return "\(minutes)m"
                    }
                }()

                let insulinFraction: CGFloat = {
                    guard let insulinHours = state.insulinHours,
                          let insulinAgeOption = InsulinAgeOption(rawValue: state.insulinAgeOption)
                    else {
                        return 0.0
                    }
                    let remainingHours = insulinAgeOption.maxInsulinAge - insulinHours
                    return remainingHours <= 1 ? 1.0 : CGFloat(min(max(
                        remainingHours / insulinAgeOption.maxInsulinAge,
                        0.0
                    ), 1.0))
                }()

                let insulinColor: Color = {
                    guard let insulinHours = state.insulinHours,
                          let insulinAgeOption = InsulinAgeOption(rawValue: state.insulinAgeOption)
                    else {
                        return .clear
                    }

                    let maxInsulinAge = insulinAgeOption.maxInsulinAge
                    let warningThreshold = maxInsulinAge * 0.75
                    let dangerThreshold = maxInsulinAge * 0.85

                    if insulinHours >= maxInsulinAge {
                        return .red
                    }

                    switch insulinHours {
                    case dangerThreshold...:
                        return .red
                    case warningThreshold ..< dangerThreshold:
                        return .yellow
                    default:
                        return .white.opacity(0.5)
                    }
                }()

                let shouldBlink: Bool = {
                    guard let insulinHours = state.insulinHours,
                          let insulinAgeOption = InsulinAgeOption(rawValue: state.insulinAgeOption)
                    else {
                        return false
                    }
                    return (insulinAgeOption.maxInsulinAge - insulinHours) <= 1
                }()

                ZStack {
                    FillablePieSegment(
                        pieSegmentViewModel: insulinAgePieSegmentViewModel,
                        // fillFraction: insulinFraction,
                        color: shouldBlink ? .red : insulinColor,
                        backgroundColor: .clear,
                        displayText: insulinDisplayText,
                        symbolSize: 25,
                        symbol: "cross.vial",
                        animateProgress: true,
                        button3D: state.button3D,
                        button3DBackground: state.button3DBackground,
                        incidenceOfLight: state.incidenceOfLight,
                        lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                            .atriumview,
                        fillFraction: insulinFraction,
                        symbolBackgroundColor: backgroundColor
                    )
                    .frame(width: 60, height: 60)
                }
                .onAppear {
                    startInsulinBlinkAnimationIfNeeded()
                }
                .onChange(of: state.insulinHours) {
                    startInsulinBlinkAnimationIfNeeded()
                }
            }
        }

        // State-Variable in der Haupt-View hinzugefügt
        @State private var isInsulinBlinking = false

        private func startInsulinBlinkAnimationIfNeeded() {
            isInsulinBlinking = false
            guard let insulinHours = state.insulinHours,
                  let insulinAgeOption = InsulinAgeOption(rawValue: state.insulinAgeOption),
                  (insulinAgeOption.maxInsulinAge - insulinHours) <= 1 else { return }

            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                isInsulinBlinking = true
            }
        }

        struct InsulinCatheterSymbol: View {
            var body: some View {
                ZStack {
                    Image(systemName: "hockey.puck")
                        .resizable()
                        // .rotationEffect(.degrees(-50))
                        .foregroundStyle(Color(.white))
                        .frame(width: 22, height: 12)
                        .offset(x: 0, y: -1)

                    Rectangle()
                        .frame(width: 2, height: 7)
                        .foregroundStyle(Color(.white))
                        .offset(x: 0, y: 8)
                }
                .frame(width: 40, height: 40)
            }
        }

        private var cannulaAgeView: some View {
            Group {
                let cannulaDisplayText: String = {
                    guard let cannulaHours = state.cannulaHours,
                          let cannulaAgeOption = CannulaAgeOption(rawValue: state.cannulaAgeOption)
                    else {
                        return "--"
                    }

                    let remainingHours = max(cannulaAgeOption.maxCannulaAge - cannulaHours, 0)
                    let totalRemainingMinutes = Int(remainingHours * 60)
                    let days = totalRemainingMinutes / (24 * 60)
                    let hours = (totalRemainingMinutes % (24 * 60)) / 60
                    let minutes = totalRemainingMinutes % 60

                    if days >= 1 {
                        return "\(days)d\(hours)h"
                    } else if hours >= 1 {
                        return "\(hours)h\(minutes)m"
                    } else {
                        return "\(minutes)m"
                    }
                }()

                let cannulaFraction: CGFloat = {
                    if let cannulaHours = state.cannulaHours,
                       let cannulaAgeOption = CannulaAgeOption(
                           rawValue: state
                               .cannulaAgeOption
                       )
                    {
                        let remainingHours = cannulaAgeOption
                            .maxCannulaAge - cannulaHours
                        if remainingHours <= 1 {
                            return 1.0
                        } else {
                            return CGFloat(min(max(
                                remainingHours / cannulaAgeOption.maxCannulaAge,
                                0.0
                            ), 1.0))
                        }
                    } else {
                        return 0.0
                    }
                }()

                let cannulaColor: Color = {
                    if let cannulaHours = state.cannulaHours,
                       let cannulaAgeOption = CannulaAgeOption(
                           rawValue: state
                               .cannulaAgeOption
                       )
                    {
                        let maxCannulaAge = cannulaAgeOption.maxCannulaAge
                        let warningThreshold = maxCannulaAge * 0.75
                        let dangerThreshold = maxCannulaAge * 0.85

                        if cannulaHours >= maxCannulaAge {
                            return .red
                        }

                        switch CGFloat(cannulaHours) {
                        case dangerThreshold...:
                            return .red
                        case warningThreshold ..< dangerThreshold:
                            return .yellow
                        default:
                            return .white.opacity(0.5)
                        }
                    } else {
                        return .clear
                    }
                }()

                let shouldBlink: Bool = {
                    guard let cannulaHours = state.cannulaHours,
                          let cannulaAgeOption = CannulaAgeOption(rawValue: state.cannulaAgeOption)
                    else {
                        return false
                    }
                    let remainingHours = cannulaAgeOption.maxCannulaAge - cannulaHours
                    return remainingHours <= 1
                }()

                ZStack {
                    FillablePieSegment(
                        pieSegmentViewModel: cannulaPieSegmentViewModel,
                        // fillFraction: cannulaFraction,
                        color: cannulaColor,
                        backgroundColor: .clear,
                        displayText: cannulaDisplayText,
                        symbolSize: 20,
                        symbol: "InsulinCatheterSymbol",
                        animateProgress: true,
                        button3D: state.button3D,
                        button3DBackground: state.button3DBackground,
                        incidenceOfLight: state.incidenceOfLight,
                        lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                            .atriumview,
                        fillFraction: cannulaFraction,
                        symbolBackgroundColor: backgroundColor
                    )
                    .frame(width: 60, height: 60)

                    InsulinCatheterSymbol()
                        .offset(y: -1.5)
                        .modifier(BlinkingModifier(shouldBlink: shouldBlink)) }

                    .onAppear { startCannulaBlinkAnimationIfNeeded() }
                    .onChange(of: state.cannulaHours) {
                        startCannulaBlinkAnimationIfNeeded()
                    }
            }
        }

        @State private var isCannulaBlinking = false

        private func startCannulaBlinkAnimationIfNeeded() {
            isCannulaBlinking = false
            guard let cannulaHours = state.cannulaHours,
                  let cannulaAgeOption = CannulaAgeOption(rawValue: state.cannulaAgeOption),
                  (cannulaAgeOption.maxCannulaAge - cannulaHours) <= 1 else { return }

            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                isCannulaBlinking = true
            }
        }

        private var batteryAgeView: some View {
            Group {
                var batteryAgeColor: Color {
                    if let batteryHours = state.batteryHours {
                        switch batteryHours {
                        case 192...: // >8 Tage = Rot
                            return .white.opacity(0.5)
                        case 168 ..< 192: // 7-8 Tage = Gelb
                            return .white.opacity(0.5)
                        default: // <7 Tage = Weiß/Transparent
                            return .white.opacity(0.5)
                        }
                    } else {
                        return .white.opacity(0.5)
                    }
                }

                let batteryAgeText: String = {
                    if let batteryHours = state.batteryHours {
                        let totalMinutes = Int(batteryHours * 60)
                        if totalMinutes < 60 {
                            return "\(totalMinutes)min"
                        } else {
                            let days = totalMinutes / (24 * 60)
                            let hours = (totalMinutes % (24 * 60)) / 60
                            return days > 0 ? "\(days)d\(hours)h" : "\(hours)h"
                        }
                    } else {
                        return "--"
                    }
                }()

                ZStack {
                    FillablePieSegment(
                        pieSegmentViewModel: batteryAgePieSegmentViewModel,
                        // fillFraction: 1.0, // Volle Kreis-Anzeige (kein Füllstand)
                        color: batteryAgeColor,
                        backgroundColor: .clear,
                        displayText: batteryAgeText,
                        symbolSize: 25,
                        symbol: "battery.50percent",
                        animateProgress: false,
                        button3D: state.button3D,
                        button3DBackground: state.button3DBackground,
                        incidenceOfLight: state.incidenceOfLight,
                        lightGlowOverlaySelector: LightGlowOverlaySelector(
                            rawValue: state.lightGlowOverlaySelector
                        ) ?? .atriumview,
                        fillFraction: 1.0,
                        symbolRotation: -90,
                        symbolBackgroundColor: backgroundColor
                    )
                    .frame(width: 60, height: 60)
                }
            }
        }

        @StateObject private var sensorAgeSegmentViewModel = PieSegmentViewModel()
        @State private var sensorAgeText: String = ""

        private var sensorAgeDays: some View {
            Group {
                if state.displayExpiration {
                    let totalHours = state.sensorAgeDays.asInt() * 24
                    let remainingHours = max(1, totalHours - state.elapsedHours)
                    let fillFraction: CGFloat = remainingHours <= 1 ? 1.0 : CGFloat(remainingHours) / CGFloat(totalHours)

                    let sensorColor: Color = {
                        switch remainingHours {
                        case ...1: return .red // Blinkt
                        case ...24: return .red // Rot aber kein Blinken
                        case ...48: return .yellow // Gelb
                        default: return .white.opacity(0.5)
                        }
                    }()

                    let sensorAgeText: String = {
                        guard let days = state.remainingSensorDays,
                              let hours = state.remainingSensorHours,
                              let minutes = state.remainingSensorMinutes
                        else {
                            return "\(state.sensorAgeDays.asInt())d"
                        }

                        if days >= 1 {
                            return "\(days)d\(hours)h"
                        } else if hours >= 1 {
                            return "\(hours)h\(minutes)m"
                        } else {
                            return "\(minutes)m"
                        }
                    }()

                    let shouldBlink = remainingHours < 24

                    ZStack {
                        FillablePieSegment(
                            pieSegmentViewModel: sensorAgeSegmentViewModel,
                            // fillFraction: fillFraction,
                            color: shouldBlink ? .red : sensorColor,
                            backgroundColor: .clear,
                            displayText: sensorAgeText,
                            symbolSize: 25,
                            symbol: "sensor.tag.radiowaves.forward",
                            animateProgress: true,
                            button3D: state.button3D,
                            button3DBackground: state.button3DBackground,
                            incidenceOfLight: state.incidenceOfLight,
                            lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview,
                            fillFraction: fillFraction,
                            symbolBackgroundColor: backgroundColor
                        )
                        .frame(width: 60, height: 60)
                    }
                    .onAppear {
                        state.settingsDidChange(state.settingsManager.settings)
                        state.sensorAgeDays = state.settingsManager.settings.sensorAgeDays
                        startSensorBlinkAnimationIfNeeded()
                    }
                    .onChange(of: state.elapsedHours) {
                        startSensorBlinkAnimationIfNeeded()
                    }
                }
            }
        }

        private func startSensorBlinkAnimationIfNeeded() {
            isSensorBlinking = false
            guard state.displayExpiration else { return }

            let totalHours = state.sensorAgeDays.asInt() * 24
            let remainingHours = max(1, totalHours - state.elapsedHours)
            guard remainingHours < 24 else { return }

            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                isSensorBlinking = true
            }
        }

        private var BluetoothConnectionView: some View {
            Group {
                let connectionFraction: CGFloat = state.isConnected ? 1.0 : 0.0
                let displayText: String = state.isConnected ? "ON" : "OFF"

                HStack {
                    ZStack {
                        FillablePieSegment(
                            pieSegmentViewModel: connectionPieSegmentViewModel,
                            // fillFraction: connectionFraction,
                            color: Color.white.opacity(0.5),
                            backgroundColor: .clear,
                            displayText: displayText,
                            symbolSize: 25,
                            symbol: "dot.radiowaves.left.and.right",
                            animateProgress: true,
                            button3D: state.button3D,
                            button3DBackground: state.button3DBackground,
                            incidenceOfLight: state.incidenceOfLight,
                            lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview,
                            fillFraction: connectionFraction,
                            symbolBackgroundColor: backgroundColor
                        )
                        .frame(width: 60, height: 60)
                    }
                    .offset(y: -2)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: state.isConnected)
        }

        // State-Variable in der Haupt-View hinzugefügt
        @State private var isSensorBlinking = false

        // danaBar Max Modules Ende

        //  TopBar Marquee

        var danaBarMarquee: some View {
            Group {
                if state.danaBar {
                    MarqueeText(
                        text: createMarqueeText(),
                        fontSize: 15,
                        textColor: .white,
                        startDelay: 1.5,
                        animationDuration: 20.0
                    )
                    .frame(width: 420)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
            }
        }

        // Helper for danaBar Marquee Start

        struct MarqueeText: View {
            var text: String
            var fontSize: CGFloat = 15
            var textColor: Color = .white
            var startDelay: Double = 2.0
            var animationDuration: Double = 10.0

            @State private var offset: CGFloat = 0
            @State private var textWidth: CGFloat = 0
            @State private var containerWidth: CGFloat = 0

            var body: some View {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Unsichtbare Breitenmessung
                        Text(text)
                            .font(.system(size: fontSize))
                            .lineLimit(1)
                            .fixedSize()
                            .background(GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        textWidth = geo.size.width
                                        containerWidth = geometry.size.width
                                        startAnimation()
                                    }
                            })
                            .hidden()

                        // Sichtbarer Lauftext
                        Text(text)
                            .font(.system(size: fontSize))
                            .foregroundColor(textColor)
                            .lineLimit(1)
                            .fixedSize()
                            .offset(x: offset)
                    }
                    .frame(width: containerWidth)
                    .clipped()
                }
                .frame(height: fontSize * 1.5)
            }

            private func startAnimation() {
                offset = containerWidth // Startposition rechts

                DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                    withAnimation(
                        .linear(duration: animationDuration)
                            .repeatForever(autoreverses: false)
                    ) {
                        offset = -textWidth // Endposition links
                    }
                }
            }
        }

        private func createMarqueeText() -> String {
            var components = [String]()

            // Insulin Age
            if let insulinHours = state.insulinHours,
               let option = InsulinAgeOption(rawValue: state.insulinAgeOption)
            {
                let remaining = option.maxInsulinAge - insulinHours
                components.append("Insulin Age left: \(formatHours(remaining))")
            }

            // Cannula Age
            if let cannulaHours = state.cannulaHours,
               let option = CannulaAgeOption(rawValue: state.cannulaAgeOption)
            {
                let remaining = option.maxCannulaAge - cannulaHours
                components.append("Cannula Age left: \(formatHours(remaining))")
            }

            // Sensor
            if state.displayExpiration {
                if let days = state.remainingSensorDays,
                   let hours = state.remainingSensorHours,
                   let minutes = state.remainingSensorMinutes
                {
                    components.append("Sensor Age left: \(formatSensorTime(days: days, hours: hours, minutes: minutes))")
                } else {
                    components.append("Sensor Age left: \(state.sensorAgeDays.asInt())d")
                }
            }

            return components.joined(separator: " | ")
        }

        private func formatHours(_ hours: Double) -> String {
            let days = Int(hours) / 24
            let remainingHours = Int(hours) % 24
            return days > 0 ? "\(days)d\(remainingHours)h" : "\(remainingHours)h"
        }

        private func formatBatteryTime(_ hours: Double) -> String {
            let totalMinutes = Int(hours * 60)
            if totalMinutes < 60 {
                return "\(totalMinutes)min"
            } else {
                let days = totalMinutes / (24 * 60)
                let hours = (totalMinutes % (24 * 60)) / 60
                return days > 0 ? "\(days)d\(hours)h" : "\(hours)h"
            }
        }

        private func formatSensorTime(days: Int, hours: Int, minutes: Int) -> String {
            if days >= 1 {
                return "\(days)d\(hours)h"
            } else if hours >= 1 {
                return "\(hours)h\(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }

        // Helper for danaBar Marquee End

        // danaBarStandard 2

        var danaBarStandard2: some View {
            Group {
                if state.danaBar {
                    HStack(spacing: 15) {
                        // Insulin Age
                        if let insulinHours = state.insulinHours,
                           let option = InsulinAgeOption(rawValue: state.insulinAgeOption)
                        {
                            let maxInsulinAge = option.maxInsulinAge
                            let remainingHours = max(maxInsulinAge - insulinHours, 0)

                            let incidenceOfLight = state.incidenceOfLight
                            let lightGlowOverlaySelector = LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview

                            let insulinColor: Color = {
                                if insulinHours >= maxInsulinAge { return .red }
                                // Umrechnung Stunden in Minuten (präziser)
                                let remainingMinutes = remainingHours * 60

                                switch remainingMinutes {
                                case ...120: // ≤ 2 Stunden (120 Minuten)
                                    return .red
                                case 121 ... 720: // 2.01h bis 12h (121-720 Minuten)
                                    return .white
                                default: // > 12 Stunden
                                    return .white
                                }
                            }()

                            HStack(spacing: 4) {
                                ZStack {
                                    if state.button3D {
                                        let glowColor1 = incidenceOfLight
                                            ? lightGlowOverlaySelector.highlightColor
                                            : Color.white.opacity(0.9)

                                        let glowColor2 = incidenceOfLight
                                            ? lightGlowOverlaySelector.highlightColor
                                            : Color.white.opacity(0.4)

                                        if state.button3DBackground {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                                        }

                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        glowColor1.opacity(0.9),
                                                        glowColor2.opacity(0.6),
                                                        Color.clear,
                                                        Color.black.opacity(0.3),
                                                        Color.black.opacity(0.6)
                                                    ]),
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1
                                            )
                                            .frame(width: 40, height: 40)
                                    } else {
                                        if state.button3DBackground {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                                        } else {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                        }
                                    }

                                    if remainingHours <= 0 {
                                        BigVialView(color: insulinColor)
                                    } else {
                                        NormalVialView(
                                            color: insulinColor,
                                            button3D: state.button3D,
                                            button3DBackground: state.button3DBackground,
                                            incidenceOfLight: state.incidenceOfLight,
                                            lightGlowOverlaySelector: LightGlowOverlaySelector(
                                                rawValue: state
                                                    .lightGlowOverlaySelector
                                            ) ??
                                                .atriumview
                                        )
                                    }
                                }
                                .frame(width: 40, height: 40)

                                Text(formatTime(remainingHours))
                                    .foregroundColor(.white)
                            }
                        }
                        // Cannula
                        if let cannulaHours = state.cannulaHours,
                           let option = CannulaAgeOption(rawValue: state.cannulaAgeOption)
                        {
                            let maxHours = option.maxCannulaAge
                            let remainingHours = max(maxHours - cannulaHours, 0)

                            let incidenceOfLight = state.incidenceOfLight
                            let lightGlowOverlaySelector = LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview

                            let cannulaColor: Color = {
                                if cannulaHours >= maxHours { return .red }

                                let remainingMinutes = remainingHours * 60

                                switch remainingMinutes {
                                case ...120:
                                    return .red
                                case 121 ... 720:
                                    return .white
                                default: // > 12 Stunden
                                    return .white
                                }
                            }()

                            HStack(spacing: 4) {
                                ZStack {
                                    if state.button3D {
                                        let glowColor1 = incidenceOfLight
                                            ? lightGlowOverlaySelector.highlightColor
                                            : Color.white.opacity(0.9)

                                        let glowColor2 = incidenceOfLight
                                            ? lightGlowOverlaySelector.highlightColor
                                            : Color.white.opacity(0.4)

                                        if state.button3DBackground {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                                        }

                                        // Glow-Effekt-Ring
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        glowColor1.opacity(0.9),
                                                        glowColor2.opacity(0.6),
                                                        Color.clear,
                                                        Color.black.opacity(0.3),
                                                        Color.black.opacity(0.6)
                                                    ]),
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1
                                            )
                                            .frame(width: 40, height: 40)
                                    } else {
                                        if state.button3DBackground {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                                        } else {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                        }
                                    }

                                    if remainingHours <= 0 {
                                        BigFluidBagView(color: cannulaColor)
                                    } else {
                                        NormalFluidBagView(
                                            color: cannulaColor,
                                            button3D: state.button3D,
                                            button3DBackground: state.button3DBackground,
                                            incidenceOfLight: state.incidenceOfLight,
                                            lightGlowOverlaySelector: LightGlowOverlaySelector(
                                                rawValue: state
                                                    .lightGlowOverlaySelector
                                            ) ??
                                                .atriumview
                                        )
                                    }
                                }
                                .frame(width: 40, height: 40)

                                Text(formatTime(remainingHours))
                                    .foregroundColor(.white)
                            }
                        }
                        // Sensor
                        if state.displayExpiration {
                            let incidenceOfLight = state.incidenceOfLight
                            let lightGlowOverlaySelector = LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview

                            HStack(spacing: 4) {
                                ZStack {
                                    if state.button3D {
                                        let glowColor1 = incidenceOfLight
                                            ? lightGlowOverlaySelector.highlightColor
                                            : Color.white.opacity(0.9)

                                        let glowColor2 = incidenceOfLight
                                            ? lightGlowOverlaySelector.highlightColor
                                            : Color.white.opacity(0.4)

                                        if state.button3DBackground {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                                        }

                                        // Glow-Effekt-Ring
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        glowColor1.opacity(0.9),
                                                        glowColor2.opacity(0.6),
                                                        Color.clear,
                                                        Color.black.opacity(0.3),
                                                        Color.black.opacity(0.6)
                                                    ]),
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1
                                            )
                                            .frame(width: 40, height: 40)
                                    } else {
                                        if state.button3DBackground {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                                        } else {
                                            Circle()
                                                .fill(Color.black.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                        }
                                    }

                                    if shouldBlink {
                                        BigSensorView(
                                            color: sensorColor
                                        )

                                    } else {
                                        NormalSensorView(
                                            color: sensorColor,
                                            button3D: state.button3D,
                                            button3DBackground: state.button3DBackground,
                                            incidenceOfLight: state.incidenceOfLight,
                                            lightGlowOverlaySelector: LightGlowOverlaySelector(
                                                rawValue: state
                                                    .lightGlowOverlaySelector
                                            ) ??
                                                .atriumview
                                        )
                                    }
                                }
                                .frame(width: 40, height: 40)

                                Text(formatSensorTime())
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .font(.system(size: 16, weight: .light, design: .default))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
            }
        }

        // MARK: - Helper-Views for danaBarClassic Anfang

        struct BigVialView: View {
            var color: Color
            var body: some View {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 45))
                    .foregroundColor(color)
                    .offset(y: -2.5)
            }
        }

        struct NormalVialView: View {
            var color: Color
            var button3D: Bool
            var button3DBackground: Bool
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector
            var body: some View {
                Image(systemName: "cross.vial")
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
        }

        private struct BigFluidBagView: View {
            var color: Color
            var body: some View {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 45))
                    .foregroundColor(color)
                    .offset(y: -2.5)
            }
        }

        private struct NormalFluidBagView: View {
            var color: Color
            var button3D: Bool
            var button3DBackground: Bool
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector
            var body: some View {
                Image(systemName: "drop.fill")
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
        }

        private struct BigSensorView: View {
            var color: Color
            var body: some View {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 45))
                    .foregroundColor(color)
                    .offset(y: -2.5)
            }
        }

        private struct NormalSensorView: View {
            var color: Color
            var button3D: Bool
            var button3DBackground: Bool
            var incidenceOfLight: Bool
            var lightGlowOverlaySelector: LightGlowOverlaySelector

            var body: some View {
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
        }

        private func formatTime(_ hours: Double) -> String {
            let totalMinutes = Int(hours * 60)
            let days = totalMinutes / (24 * 60)
            let hours = (totalMinutes % (24 * 60)) / 60
            let minutes = totalMinutes % 60

            if days >= 1 {
                return "\(days)d\(hours)h"
            } else if hours >= 1 {
                return "\(hours)h"
            } else {
                return "\(minutes)m"
            }
        }

        private func formatSensorTime() -> String {
            guard let days = state.remainingSensorDays,
                  let hours = state.remainingSensorHours,
                  let minutes = state.remainingSensorMinutes
            else {
                return "--"
            }

            let totalHours = Double(days * 24 + hours) + Double(minutes) / 60.0
            return formatTime(totalHours)
        }

        // SENSOR
        private var shouldBlink: Bool { // Dient nur noch zur Steuerung des Icons in der SensorView
            guard state.displayExpiration,
                  let days = state.remainingSensorDays,
                  let hours = state.remainingSensorHours,
                  let minutes = state.remainingSensorMinutes
            else { return false }

            // Gesamtrestzeit in Stunden
            let totalRemaining = Double(days * 24 + hours) + Double(minutes) / 60.0
            return totalRemaining <= 6.0 // Stellschraube wann er zum großen Icon wechselt
        }

        private var sensorRemainingTime: String {
            guard let days = state.remainingSensorDays,
                  let hours = state.remainingSensorHours,
                  let minutes = state.remainingSensorMinutes
            else {
                return "--"
            }
            return formatSensorTime(days: days, hours: hours, minutes: minutes)
        }

        private var sensorColor: Color {
            if state.displayExpiration {
                guard let days = state.remainingSensorDays,
                      let hours = state.remainingSensorHours,
                      let minutes = state.remainingSensorMinutes
                else { return .white }

                // Gesamtverbleibende Zeit in Minuten berechnen
                let totalMinutes = (days * 24 * 60) + (hours * 60) + minutes

                switch totalMinutes {
                case ...120: // ≤ 2 Stunden (0-120 Minuten)
                    return .red
                case 121 ... 720:
                    return .yellow
                default: // > 12 Stunden
                    return .white
                }
            } else {
                return state.sensorAgeDays.asInt() > 13 ? .yellow : .white
            }
        }

        // MARK: - Helper-Views for danaBarClassic Ende

        @State private var timerInterval: TimeInterval = 2 // Startet nach 2 Sekunden
        @State private var timer: Timer? = nil

        func startTimer() {
            timer?.invalidate() // Falls ein vorheriger Timer existiert, wird er gestoppt
            timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { _ in
                state.specialDanaKitFunction()
                state.updateRemainingSensorDays()
                // Nach 15 Sekunden auf 60 Sekunden Intervall wechseln
                if timerInterval == 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                        timerInterval = 60
                        startTimer()
                    }
                }
            }
        }

        // TopBars Ende

        var mainChart: some View {
            let isChartBackgroundColored: Bool = state.settingsManager?.settings.chartBackgroundColored ?? false

            return Group {
                if isChartBackgroundColored {
                    ZStack {
                        ColouredBackground()

                        if state.animatedBackground {
                            SpriteView(scene: spriteScene, options: [.allowsTransparency])
                                .ignoresSafeArea()
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        }
                        MainChartView(data: state.data, triggerUpdate: $triggerUpdate)
                    }
                } else {
                    ZStack {
                        ColouredBackground2()

                        if state.animatedBackground {
                            SpriteView(scene: spriteScene, options: [.allowsTransparency])
                                .ignoresSafeArea()
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        }
                        MainChartView(data: state.data, triggerUpdate: $triggerUpdate)
                    }
                }
            }
            .padding(.bottom, 5)
            .padding(.leading, 15)
            .padding(.trailing, 15)
            .modal(for: .dataTable, from: self)
        }

        var chart: some View {
            VStack(spacing: 0) {
                Group {
                    switch DanaBarOption(rawValue: state.danaBarOption) ?? .max {
                    case .max:
                        danaBarMax
                            .padding(.vertical, 10)
                            .padding(.top, 20)
                    case .marquee:
                        danaBarMarquee
                            .padding(.vertical, 10)
                            .padding(.top, 20)
                    case .standard:
                        danaBarStandard
                            .padding(.vertical, 10)
                            .padding(.top, 20)
                    case .standard2:
                        danaBarStandard2
                            .padding(.vertical, 10)
                            .padding(.top, 20)
                    }
                    mainChart.padding(.top, 35)
                    tempTargetbar.padding(.top, 35)
                    bottomBar.padding(.top, 20).padding(.bottom, 10)
                        .frame(width: UIScreen.main.bounds.width)
                }
            }
            .frame(minHeight: UIScreen.main.bounds.height / 1.7) // Je größer der Wert, desto kleiner der mainChart
        }

        var tempTargetbar: some View {
            ZStack {
                if state.tempTargetbar {
                    Targetbar
                } else {}
            }
            .frame(maxWidth: .infinity, maxHeight: state.tempTargetbar ? 25 : 0)
        }

        var Targetbar: some View {
            HStack {
                if state.pumpSuspended {
                    Text("Pump suspended")
                        .font(.extraSmall)
                        .bold()
                        .foregroundStyle(Color.orange)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.3, alignment: .leading)
                        .frame(height: 20)
                }

                if let tempTargetString = tempTargetString, !(fetchedPercent.first?.enabled ?? false) {
                    Text(tempTargetString)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.4, alignment: .center)
                        .frame(height: 20)
                } else {
                    profileView
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.4, alignment: .center)
                        .frame(height: 20)
                }

                if state.closedLoop, state.maxIOB == 0 {
                    Text("Check Max IOB Setting")
                        .font(.extraSmall)
                        .foregroundColor(.orange)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.3, alignment: .trailing)
                }
            }

            .background(
                TimeEllipse(
                    characters: 17,
                    button3D: state.button3D,
                    button3DBackground: state.button3DBackground,
                    incidenceOfLight: state.incidenceOfLight,
                    lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ?? .atriumview
                )
            )
        }

        // BottomInfoBar Start
        var bottomBar: some View {
            Group {
                if state.timeSettings {
                    HStack(spacing: 15) {
                        // Linker Stack
                        Spacer()
                        HStack {
                            isfView
                                .foregroundColor(.white)
                        }
                        .padding(.leading, 0)
                        .frame(maxWidth: 100, alignment: .leading)

                        Spacer()

                        // Mittlerer Stack
                        HStack(spacing: 0) {
                            timeSetting
                        }

                        Spacer()

                        // Rechter Stack - TDD
                        HStack {
                            tddView
                                .foregroundColor(.white)
                        }
                        .padding(.trailing, 25)
                        .frame(maxWidth: 100, alignment: .trailing)

                        Spacer()
                    }
                } else {
                    EmptyView()
                }
            }
        }

        private var sensitivityPercentage: String {
            let sensitivityValue = (state.data.suggestion?.sensitivityRatio ?? 1) as NSDecimalNumber
            return percentageFormatter.string(from: NSNumber(value: sensitivityValue.doubleValue * 100)) ?? "0"
        }

        private var isfView: some View {
            ZStack {
                HStack {
                    HStack {
                        Text("ISF")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)

                        Text("\(sensitivityPercentage)%")
                            .foregroundStyle(.white)
                            .font(.timeSettingFont)
                    }
                    .background(
                        TimeEllipse(
                            characters: 12,
                            button3D: state.button3D,
                            button3DBackground: state.button3DBackground,
                            incidenceOfLight: state.incidenceOfLight,
                            lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                                .atriumview
                        )
                    )
                    .onTapGesture {
                        if state.autoisf {
                            displayAutoHistory.toggle()
                        } else {
                            displayDynamicHistory.toggle()
                        }
                    }
                }
                .offset(x: 30)
            }
        }

        var timeSetting: some View {
            let string = "\(state.hours) " + NSLocalizedString("hours", comment: "") + "   "
            return Menu(string) {
                Button("3 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 3 })
                Button("6 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 6 })
                Button("9 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 9 })
                Button("12 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 12 })
                Button("24 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 24 })
                Button("UI/UX Settings", action: { state.showModal(for: .statisticsConfig) })
            }
            .foregroundStyle(Color.white)
            .font(.timeSettingFont)
            .padding(.vertical, 15)
            .background(
                TimeEllipse(
                    characters: 12,
                    button3D: state.button3D,
                    button3DBackground: state.button3DBackground,
                    incidenceOfLight: state.incidenceOfLight,
                    lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ?? .atriumview
                )
            ) }

        private var tddView: some View {
            ZStack {
                HStack {
                    Image(systemName: "circle.slash").font(.system(size: 13)).foregroundStyle(.white)

                    Text("\(targetFormatter.string(from: state.tddActualAverage as NSNumber) ?? "0") U")
                        .foregroundStyle(.white)
                }
                .font(.timeSettingFont)
                .background(
                    TimeEllipse(
                        characters: 13,
                        button3D: state.button3D,
                        button3DBackground: state.button3DBackground,
                        incidenceOfLight: state.incidenceOfLight,
                        lightGlowOverlaySelector: LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                            .atriumview
                    )
                )
            }
        }

        // BottomInfoBar End

        // ButtonPanel Start
        @State private var didLongPress = false

        // buttonWithCircle Funktion
        @ViewBuilder private func buttonWithCircle(
            iconName: String,
            isSFSymbol: Bool = true,
            symbolRenderingMode: SymbolRenderingMode? = .hierarchical,
            colors: [Color] = [.white],
            circleColor _: Color,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                ZStack {
                    let incidenceOfLight = state.incidenceOfLight
                    let lightGlowOverlaySelector = LightGlowOverlaySelector(rawValue: state.lightGlowOverlaySelector) ??
                        .atriumview

                    // 3D-Button-Hintergrund
                    if state.button3D {
                        let glowColor1 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.9)

                        let glowColor2 = incidenceOfLight
                            ? lightGlowOverlaySelector.highlightColor
                            : Color.white.opacity(0.4)

                        if state.button3DBackground {
                            Circle()
                                .fill(Color.black.opacity(0.2))
                                .frame(width: 50, height: 50)
                                .shadow(color: Color.black.opacity(0.4), radius: 5, x: 3, y: 3)
                        }

                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        glowColor1.opacity(0.5),
                                        glowColor2.opacity(0.3),
                                        Color.clear,
                                        Color.black.opacity(0.3),
                                        Color.black.opacity(0.6)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .frame(width: 50, height: 50)
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(Circle().stroke(Color.white, lineWidth: 0))
                    }

                    // Spezielles Styling für fork.knife
                    if iconName == "fork.knife.custom" {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 30, height: 30)

                            Image(systemName: "fork.knife")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.orange)
                                .font(.system(size: 20))
                        }
                        .font(.system(size: 20))
                    }

                    // Spezielles Styling für Syringe
                    if iconName == "syringe.custom" {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 30, height: 30)

                            Image(systemName: "syringe")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.blue)
                                .font(.system(size: 20))
                        }
                        .font(.system(size: 20))
                    }

                    // SF Symbol Darstellung mit direkter Farbanwendung
                    else if isSFSymbol {
                        Group {
                            switch colors.count {
                            case 1:
                                Image(systemName: iconName)
                                    .symbolRenderingMode(symbolRenderingMode)
                                    .foregroundStyle(colors[0])
                            case 2:
                                Image(systemName: iconName)
                                    .symbolRenderingMode(symbolRenderingMode)
                                    .foregroundStyle(colors[0], colors[1])
                            case 3:
                                Image(systemName: iconName)
                                    .symbolRenderingMode(symbolRenderingMode)
                                    .foregroundStyle(colors[0], colors[1], colors[2])
                            default:
                                Image(systemName: iconName)
                                    .symbolRenderingMode(symbolRenderingMode)
                                    .foregroundStyle(colors.first ?? .white)
                            }
                        }
                        .font(.system(size: 25, weight: .medium))
                        .frame(width: 40, height: 40)
                    }
                    // Fallback für Asset-Icons
                    else {
                        Image(iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                    }
                }
            }
            .buttonStyle(.borderless)
            .contentShape(Circle())
        }

        // ButtonPanel mit modernen SF Symbols für iOS 17
        @ViewBuilder private func buttonPanel(_ geo: GeometryProxy) -> some View {
            ZStack {
                backgroundColor
                    .frame(height: 60 + geo.safeAreaInsets.bottom)

                let isOverride = fetchedPercent.first?.enabled ?? false
                let isTarget = (state.tempTarget != nil)

                HStack {
                    // Carb Button
                    if state.carbButton {
                        ZStack {
                            buttonWithCircle(
                                iconName: "fork.knife.custom",
                                symbolRenderingMode: .palette,
                                colors: [.orange, .clear],
                                circleColor: Color.black.opacity(1.0)
                            ) {
                                state.showModal(for: .addCarbs(editMode: false, override: false))
                            }

                            if let carbsReq = state.carbsRequired {
                                Text(numberFormatter.string(from: carbsReq as NSNumber)!)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Capsule().fill(Color.red))
                                    .offset(x: 20, y: 10)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // IOB Button
                    buttonWithCircle(
                        iconName: "syringe.custom",
                        colors: [.blue, .clear], // [Spritzenfarbe, Kreisfarbe]
                        circleColor: Color.black.opacity(1.0)
                    ) {
                        (state.bolusProgress != nil) ? showBolusActiveAlert = true :
                            state.showModal(for: .bolus(
                                waitForSuggestion: state.useCalc ? true : false,
                                fetch: false
                            ))
                    }
                    .frame(maxWidth: .infinity)

                    // Manual Temp Basal Button
                    if state.allowManualTemp {
                        buttonWithCircle(
                            iconName: "speedometer",
                            symbolRenderingMode: .monochrome,
                            colors: [.gray],
                            circleColor: Color.black.opacity(1.0)
                        ) {
                            state.showModal(for: .manualTempBasal)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Profile Button
                    if state.profileButton {
                        buttonWithCircle(
                            iconName: isOverride ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle",
                            symbolRenderingMode: .palette,
                            colors: [.purple, isOverride ? .green : .gray],
                            circleColor: Color.black.opacity(1.0)
                        ) {
                            if isOverride {
                                showCancelAlert.toggle()
                            } else {
                                state.showModal(for: .overrideProfilesConfig)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Target Button
                    if state.useTargetButton {
                        buttonWithCircle(
                            iconName: "scope",
                            symbolRenderingMode: .palette,
                            colors: [isTarget ? .red : .white, .clear],
                            circleColor: Color.black.opacity(1.0)
                        ) {
                            if isTarget {
                                showCancelTTAlert.toggle()
                            } else {
                                state.showModal(for: .addTempTarget)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // UI/UX Button
                    buttonWithCircle(
                        /* iconName: "uiwindow.split.2x1",
                         symbolRenderingMode: .hierarchical,
                         colors: [.indigo],*/

                        iconName: "square.3.layers.3d",
                        symbolRenderingMode: .palette,
                        colors: [.purple, .blue],

                        /*  iconName: "paintpalette.fill",
                            symbolRenderingMode: .palette,
                            colors: [.teal, .mint],*/

                        /*  iconName: "slider.horizontal.3",
                            symbolRenderingMode: .palette,
                            colors: [.gray, .blue],*/
                        circleColor: Color.black.opacity(1.0)
                    ) {
                        state.showModal(for: .statisticsConfig)
                    }
                    .frame(maxWidth: .infinity)

                    // Settings Button
                    buttonWithCircle(
                        iconName: "gearshape.fill",
                        symbolRenderingMode: .hierarchical,
                        colors: [.gray],
                        circleColor: Color.black.opacity(1.0)
                    ) {
                        if !didLongPress {
                            state.showModal(for: .settings)
                        }
                        didLongPress = false
                    }
                    .simultaneousGesture(
                        LongPressGesture().onEnded { _ in
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.isStatusPopupPresented.toggle()
                            didLongPress = true
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 15)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .confirmationDialog("Cancel Profile Override", isPresented: $showCancelAlert) {
                Button("Cancel Profile Override", role: .destructive) {
                    state.cancelProfile()
                    triggerUpdate.toggle()
                }
            }
            .confirmationDialog("Cancel Temporary Target", isPresented: $showCancelTTAlert) {
                Button("Cancel Temporary Target", role: .destructive) {
                    state.cancelTempTarget()
                }
            }
            .padding(.bottom, 20)
        }

        var tempBasalString: String? {
            guard let tempRate = state.tempRate else {
                return nil
            }
            let rateString = numberFormatter.string(from: tempRate as NSNumber) ?? "0"
            var manualBasalString = ""

            if state.apsManager.isManualTempBasal {
                manualBasalString = NSLocalizedString(
                    " Manual",
                    comment: "Manual Temp basal"
                )
            }
            return rateString + " " + NSLocalizedString(" U/hr", comment: "Unit per hour with space") + manualBasalString
        }

        var tempTargetString: String? {
            guard let tempTarget = state.tempTarget else {
                return nil
            }
            return tempTarget.displayName
        }

        var profileView: some View {
            HStack(spacing: 0) {
                if let override = fetchedPercent.first {
                    if override.enabled {
                        if override.isPreset {
                            let profile = fetchedProfiles.first(where: { $0.id == override.id })
                            if let currentProfile = profile {
                                if let name = currentProfile.name, name != "EMPTY", name.nonEmpty != nil, name != "",
                                   name != "\u{0022}\u{0022}"
                                {
                                    if name.count > 15 {
                                        let shortened = name.prefix(15)
                                        Text(shortened).font(.system(size: 15)).foregroundStyle(Color.white)
                                    } else {
                                        Text(name).font(.system(size: 15)).foregroundStyle(Color.white)
                                    }
                                }
                            } // else { Text("📉") }
                            else {
                                Image(systemName: "chart.line.downtrend.xyaxis")
                                    .foregroundColor(.red)
                                    .offset(y: -1)
                            }
                        } else if override.percentage != 100 {
                            Text(override.percentage.formatted() + " %").font(.statusFont).foregroundStyle(.secondary)
                        } else if override.smbIsOff, !override.smbIsAlwaysOff {
                            Text("No ").font(.statusFont).foregroundStyle(.secondary)
                            Image(systemName: "syringe")
                                .font(.previewNormal).foregroundStyle(.secondary)
                        } else if override.smbIsOff {
                            Image(systemName: "clock").font(.statusFont).foregroundStyle(.secondary)
                            Image(systemName: "syringe")
                                .font(.previewNormal).foregroundStyle(.secondary)
                        } else {
                            Text("Override").font(.statusFont).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        // ButtonPanel End

        var DayView: some View {
            let isChartBackgroundColored: Bool = state.settingsManager?.settings.chartBackgroundColored ?? false
            let backgroundView = isChartBackgroundColored ? AnyView(ColouredBackground()) : AnyView(ColouredBackground2())

            return Group {
                ZStack {
                    if !state.skipGlucoseChart {
                        backgroundView
                        glucoseHeaderView().padding(.top, 8).padding(.bottom, 10)
                    } else {
                        EmptyView()
                    }
                }

                ZStack {
                    backgroundView
                    preview.padding(.top, 15)
                }

                ZStack {
                    backgroundView
                    loopPreview
                }

                if !state.iobData.isEmpty {
                    ZStack {
                        backgroundView
                        activeCOBView.padding(.bottom, 20)
                    }

                    ZStack {
                        backgroundView
                        activeIOBView.padding(.bottom, 20)
                    }
                }
            }
            .padding(.horizontal, 15)
        }

        @ViewBuilder private func glucoseHeaderView() -> some View {
            ColouredBackground2()
                .frame(maxHeight: 200)

            VStack {
                glucosePreview
            }
            .clipShape(Rectangle())
            .foregroundStyle(Color.white)
        }

        var glucosePreview: some View {
            let data = state.data.glucose
            let minimum = data.compactMap(\.glucose).min() ?? 0
            let minimumRange = Double(minimum) * 0.8
            let maximum = Double(data.compactMap(\.glucose).max() ?? 0) * 1.1

            let high = state.data.highGlucose
            let low = state.data.lowGlucose
            let veryHigh = 198

            return Chart(data) {
                PointMark(
                    x: .value("Time", $0.dateString),
                    y: .value("Glucose", Double($0.glucose ?? 0) * (state.data.units == .mmolL ? 0.0555 : 1.0))
                )
                .foregroundStyle(
                    (($0.glucose ?? 0) > veryHigh || Decimal($0.glucose ?? 0) < low) ? Color.red : Decimal($0.glucose ?? 0) >
                        high ? Color.yellow : Color.green
                )
                .symbolSize(5)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.white)
                    AxisTick().foregroundStyle(Color.white)
                    AxisValueLabel().foregroundStyle(Color.white)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.white)
                    AxisTick().foregroundStyle(Color.white)
                    AxisValueLabel().foregroundStyle(Color.white)
                }
            }
            .chartYScale(
                domain: minimumRange * (state.data.units == .mmolL ? 0.0555 : 1.0) ... maximum *
                    (state.data.units == .mmolL ? 0.0555 : 1.0)
            )
            .chartXScale(
                domain: Date.now.addingTimeInterval(-1.days.timeInterval) ... Date.now
            )
            .frame(height: 100)
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.large)
        }

        var preview: some View {
            VStack {
                Text("Time In Range")
                    .font(.previewHeadline)
                    .foregroundColor(.white)

                ZStack {
                    VStack {
                        PreviewChart(
                            readings: $state.readings,
                            lowLimit: $state.data.lowGlucose,
                            highLimit: $state.data.highGlucose
                        )
                        .padding()
                    }
                }
                .padding(.vertical, 5)
            }
            .onTapGesture {
                state.showModal(for: .statistics)
            }
        }

        var loopPreview: some View {
            ColouredBackground2()
                .frame(minHeight: 190)
                .overlay {
                    LoopsView(loopStatistics: $state.loopStatistics)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 10)
                .foregroundStyle(Color.white)
                .onTapGesture {
                    state.showModal(for: .statistics)
                }
        }

        var activeIOBView: some View {
            ColouredBackground2()
                .frame(minHeight: 430)
                .overlay {
                    ActiveIOBView(
                        data: $state.iobData,
                        neg: $state.neg,
                        tddChange: $state.tddChange,
                        tddAverage: $state.tddAverage,
                        tddYesterday: $state.tddYesterday,
                        tdd2DaysAgo: $state.tdd2DaysAgo,
                        tdd3DaysAgo: $state.tdd3DaysAgo,
                        tddActualAverage: $state.tddActualAverage
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 10)
                .foregroundStyle(Color.white)
        }

        var activeCOBView: some View {
            ColouredBackground2()
                .frame(minHeight: 230)
                .overlay {
                    ActiveCOBView(data: $state.iobData)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
        }

        var backgroundColor: Color {
            BackgroundColorOption(rawValue: state.backgroundColorOptionRawValue)?.color ?? .black
        }

        var body: some View {
            GeometryReader { geo in
                if onboarded.first?.firstRun ?? true, let openAPSSettings = state.openAPSSettings {
                    importResetSettingsView(settings: openAPSSettings)
                } else {
                    VStack(spacing: 0) {
                        headerView(geo)
                        ScrollView {
                            ScrollViewReader { _ in
                                LazyVStack {
                                    chart.padding(.top, 10)
                                    DayView.padding(.bottom, 40).padding(.top, 30)
                                }
                                .background(
                                    GeometryReader { proxy in
                                        let scrollPosition = proxy.frame(in: .named("HomeScrollView")).minY
                                        Color.clear
                                            .onChange(of: scrollPosition) { _, newValue in
                                                let yThreshold: CGFloat = -550
                                                if newValue < yThreshold {
                                                    withAnimation(.easeOut(duration: 0.3)) { display = true }
                                                } else {
                                                    withAnimation(.easeOut(duration: 0.4)) { display = false }
                                                }
                                            }
                                    }
                                )
                            }
                        }
                        .coordinateSpace(name: "HomeScrollView")
                        buttonPanel(geo)
                            .frame(height: 60)
                    }
                    .background(backgroundColor)
                    /*  .background(
                     LinearGradient(
                     gradient: Gradient(
                     stops: colorScheme == .light
                     ? [
                     .init(color: Color.cyan.opacity(0.2), location: 0.0),
                     .init(color: Color.white, location: 0.3),
                     .init(color: Color.white, location: 0.8),
                     .init(color: Color.cyan.opacity(0.2), location: 1.0)
                     ]
                     : [
                     .init(color: Color.cyan.opacity(0.3), location: 0.0),
                     .init(color: Color.black, location: 0.3),
                     .init(color: Color.black, location: 0.8),
                     .init(color: Color.cyan.opacity(0.3), location: 1.0)
                     ]
                     ),
                     startPoint: .top,
                     endPoint: .bottom
                     )*/

                    .ignoresSafeArea(edges: .vertical)
                    .onAppear {
                        startProgress()
                        startTimer() // Timer starten
                    }
                    .onDisappear {
                        timer?.invalidate() // Timer stoppen
                    }
                    .navigationTitle("Home")
                    .navigationBarHidden(true)
                    .ignoresSafeArea(.keyboard)
                    .sheet(isPresented: $displayAutoHistory) {
                        AutoISFHistoryView(units: state.data.units)
                    }
                    .sheet(isPresented: $displayDynamicHistory) {
                        DynamicHistoryView(units: state.data.units)
                            .environment(\.colorScheme, colorScheme)
                    }
                    .popup(isPresented: state.isStatusPopupPresented, alignment: .center, direction: .bottom) {
                        popup
                            .padding(10)
                            .shadow(color: .white, radius: 2, x: 0, y: 0)
                            .cornerRadius(10)
                            .onTapGesture {
                                state.isStatusPopupPresented = false
                            }
                            .gesture(
                                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                    .onEnded { value in
                                        if value.translation.height < 0 {
                                            state.isStatusPopupPresented = false
                                        }
                                    }
                            )
                    }
                    .onAppear {
                        if onboarded.first?.firstRun ?? true {
                            state.fetchPreferences()
                        }
                        configureView()
                    }
                    // )
                }
            }
        }

        var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.statusTitle).font(.suggestionHeadline).foregroundStyle(Color.white)
                    .padding(.bottom, 4)
                if let suggestion = state.data.suggestion {
                    TagCloudView(tags: suggestion.reasonParts).animation(.none, value: false)

                    Text(suggestion.reasonConclusion.capitalizingFirstLetter()).font(.suggestionSmallParts)
                        .foregroundStyle(Color.white)
                } else {
                    Text("No sugestion found").font(.suggestionHeadline).foregroundStyle(Color.white)
                }
                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Error at", comment: "") + " " + dateFormatter.string(from: date))
                        .foregroundStyle(Color.white)
                        .font(.suggestionError)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.suggestionError).fontWeight(.semibold).foregroundColor(.orange)
                } else if let suggestion = state.data.suggestion, (suggestion.bg ?? 100) == 400 {
                    Text("Invalid CGM reading (HIGH).").font(.suggestionError).bold().foregroundColor(.loopRed)
                        .padding(.top, 8)
                    Text("SMBs and High Temps Disabled.").font(.suggestionParts).foregroundStyle(Color.white)
                        .padding(.bottom, 4)
                }
            }
            .padding()
            .background(backgroundColor) // Für das Popup mit den Loop Informationen
            .cornerRadius(10)
            .shadow(radius: 2)
        }

        private func importResetSettingsView(settings: Preferences) -> some View {
            Restore.RootView(
                resolver: resolver,
                openAPS: settings
            )
        }
    }
}
