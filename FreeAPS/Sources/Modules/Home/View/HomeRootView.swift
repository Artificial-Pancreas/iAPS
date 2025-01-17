import Charts
import CoreData
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
        @State var display = false
        @State var displayGlucose = false
        @State var animateLoop = Date.distantPast
        @State var animateTIR = Date.distantPast
        @State var showBolusActiveAlert = false
        @State var displayAutoHistory = false

        let buttonFont = Font.custom("TimeButtonFont", size: 14)
        let viewPadding: CGFloat = 5

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
        @Environment(\.sizeCategory) private var fontSize

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
            entity: Onboarding.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var onboarded: FetchedResults<Onboarding>

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
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

        private var spriteScene: SKScene {
            let scene = SnowScene()
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            return scene
        }

        var glucoseView: some View {
            CurrentGlucoseView(
                recentGlucose: $state.recentGlucose,
                delta: $state.glucoseDelta,
                units: $state.data.units,
                alarm: $state.alarm,
                lowGlucose: $state.data.lowGlucose,
                highGlucose: $state.data.highGlucose,
                alwaysUseColors: $state.alwaysUseColors,
                displayDelta: $state.displayDelta,
                scrolling: $displayGlucose
            )
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

        var loopView: some View {
            LoopView(
                suggestion: $state.data.suggestion,
                enactedSuggestion: $state.enactedSuggestion,
                closedLoop: $state.closedLoop,
                timerDate: $state.data.timerDate,
                isLooping: $state.isLooping,
                lastLoopDate: $state.lastLoopDate,
                manualTempBasal: $state.manualTempBasal
            )
            .onTapGesture {
                state.isStatusPopupPresented.toggle()
            }.onLongPressGesture {
                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                impactHeavy.impactOccurred()
                state.runLoop()
            }
            .offset(y: 10)
        }

        var tempBasalString: String {
            guard let tempRate = state.tempRate else {
                return "?" + NSLocalizedString(" U/hr", comment: "Unit per hour with space")
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

        var info: some View {
            HStack(spacing: 10) {
                ZStack {
                    HStack {
                        if state.pumpSuspended {
                            Text("Pump suspended")
                                .font(.extraSmall).bold().foregroundColor(.loopGray)
                        } else {
                            Text(tempBasalString)
                                .font(.statusFont).bold()
                                .foregroundColor(.insulin)
                        }
                        if state.closedLoop, state.maxIOB == 0 {
                            Text("Check Max IOB Setting").font(.extraSmall).foregroundColor(.orange)
                        }
                    }
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let tempTargetString = tempTargetString, !(fetchedPercent.first?.enabled ?? false) {
                    Text(tempTargetString)
                        .font(.buttonFont)
                        .foregroundColor(.secondary)
                } else {
                    profileView
                }

                ZStack {
                    HStack {
                        Text("⇢").font(.statusFont).foregroundStyle(.secondary)

                        if let eventualBG = state.eventualBG {
                            Text(
                                fetchedTargetFormatter.string(
                                    from: (state.data.units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
                                ) ?? ""
                            ).font(.statusFont).foregroundColor(colorScheme == .dark ? .white : .black)
                        } else {
                            Text("?").font(.statusFont).foregroundStyle(.secondary)
                        }
                        Text(state.data.units.rawValue).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }

        var infoPanel: some View {
            info.frame(height: 26)
                .background {
                    InfoPanelBackground(colorScheme: colorScheme)
                }
        }

        var mainChart: some View {
            ZStack {
                if state.animatedBackground {
                    SpriteView(scene: spriteScene, options: [.allowsTransparency])
                        .ignoresSafeArea()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
                MainChartView(data: state.data, triggerUpdate: $triggerUpdate)
            }
            .padding(.bottom, 5)
            .modal(for: .dataTable, from: self)
        }

        @ViewBuilder private func buttonPanel(_ geo: GeometryProxy) -> some View {
            ZStack {
                addHeaderBackground()
                    .frame(height: 50 + geo.safeAreaInsets.bottom)
                let isOverride = fetchedPercent.first?.enabled ?? false
                let isTarget = (state.tempTarget != nil)
                VStack {
                    Divider()
                    HStack {
                        Button { state.showModal(for: .addCarbs(editMode: false, override: false)) }
                        label: {
                            ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                                Image(systemName: "fork.knife")
                                    .renderingMode(.template)
                                    .font(.custom("Buttons", size: 24))
                                    .foregroundColor(colorScheme == .dark ? .loopYellow : .orange)
                                    .padding(8)
                                    .foregroundColor(.loopYellow)
                                if let carbsReq = state.carbsRequired {
                                    Text(numberFormatter.string(from: carbsReq as NSNumber)!)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Capsule().fill(Color.red))
                                }
                            }
                        }.buttonStyle(.borderless)
                        Spacer()
                        Button {
                            (state.bolusProgress != nil) ? showBolusActiveAlert = true :
                                state.showModal(for: .bolus(
                                    waitForSuggestion: state.useCalc ? true : false,
                                    fetch: false
                                ))
                        }
                        label: {
                            Image(systemName: "syringe")
                                .renderingMode(.template)
                                .font(.custom("Buttons", size: 24))
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.insulin)
                        Spacer()
                        if state.allowManualTemp {
                            Button { state.showModal(for: .manualTempBasal) }
                            label: {
                                Image("bolus1")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: IAPSconfig.buttonSize, height: IAPSconfig.buttonSize, alignment: .bottom)
                            }
                            .foregroundColor(.insulin)
                            Spacer()
                        }
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image(systemName: isOverride ? "person.fill" : "person")
                                .symbolRenderingMode(.palette)
                                .font(.custom("Buttons", size: 28))
                                .foregroundStyle(.purple)
                                .padding(8)
                                .background(isOverride ? .purple.opacity(0.15) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .onTapGesture {
                            if isOverride {
                                showCancelAlert.toggle()
                            } else {
                                state.showModal(for: .overrideProfilesConfig)
                            }
                        }
                        .onLongPressGesture {
                            state.showModal(for: .overrideProfilesConfig)
                        }
                        if state.useTargetButton {
                            Spacer()
                            Image(systemName: "target")
                                .renderingMode(.template)
                                .font(.custom("Buttons", size: 24))
                                .padding(8)
                                .foregroundColor(.loopGreen)
                                .background(isTarget ? .green.opacity(0.15) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .onTapGesture {
                                    if isTarget {
                                        showCancelTTAlert.toggle()
                                    } else {
                                        state.showModal(for: .addTempTarget)
                                    }
                                }
                                .onLongPressGesture {
                                    state.showModal(for: .addTempTarget)
                                }
                        }
                        Spacer()
                        Button { state.showModal(for: .settings) }
                        label: {
                            Image(systemName: "gear")
                                .renderingMode(.template)
                                .font(.custom("Buttons", size: 24))
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.gray)
                    }
                    .padding(.horizontal, state.allowManualTemp ? 5 : 24)
                    .padding(.bottom, geo.safeAreaInsets.bottom)
                }
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
            .confirmationDialog("Bolus already in Progress", isPresented: $showBolusActiveAlert) {
                Button("Bolus already in Progress!", role: .cancel) {
                    showBolusActiveAlert = false
                }
            }
        }

        var chart: some View {
            let ratio = 1.96
            let ratio2 = 2.0

            return addColouredBackground().shadow(radius: 3, y: 3)
                .overlay {
                    mainChart
                }
                .frame(minHeight: UIScreen.main.bounds.height / (fontSize < .extraExtraLarge ? ratio : ratio2))
        }

        var carbsAndInsulinView: some View {
            HStack {
                // A temporary ugly(?) workaround for displaying last real IOB and COB computation
                let opacity: CGFloat = colorScheme == .dark ? 0.2 : 0.65
                let materialOpacity: CGFloat = colorScheme == .dark ? 0.25 : 0.10
                // Carbs on Board
                HStack {
                    let substance = Double(state.data.suggestion?.cob ?? 0)
                    let max = max(Double(state.maxCOB), 1)
                    let fraction: Double = 1 - (substance / max)
                    let fill = CGFloat(min(Swift.max(fraction, 0.05), substance > 0 ? 0.92 : 1))
                    TestTube(
                        opacity: opacity,
                        amount: fill,
                        colourOfSubstance: .loopYellow,
                        materialOpacity: materialOpacity
                    )
                    .frame(width: 12, height: 38)
                    .offset(x: 0, y: -5)
                    HStack(spacing: 0) {
                        if let loop = state.data.suggestion, let cob = loop.cob {
                            Text(numberFormatter.string(from: cob as NSNumber) ?? "0")
                                .font(.statusFont).bold()
                            // Display last loop, unless very old
                        } else {
                            Text("?").font(.statusFont).bold()
                        }
                        Text(NSLocalizedString(" g", comment: "gram of carbs")).font(.statusFont).foregroundStyle(.secondary)
                    }.offset(x: 0, y: 5)
                }
                // Instead of Spacer
                Text(" ")

                // Insulin on Board
                HStack {
                    let substance = Double(state.data.suggestion?.iob ?? 0)
                    let max = max(Double(state.maxIOB), 1)
                    let fraction: Double = 1 - abs(substance) / max
                    let fill = CGFloat(min(Swift.max(fraction, 0.05), 1))
                    TestTube(
                        opacity: opacity,
                        amount: fill,
                        colourOfSubstance: substance < 0 ? .red : .insulin,
                        materialOpacity: materialOpacity
                    )
                    .frame(width: 12, height: 38)
                    .offset(x: 0, y: -5)
                    HStack(spacing: 0) {
                        if let loop = state.data.suggestion, let iob = loop.iob {
                            Text(
                                targetFormatter.string(from: iob as NSNumber) ?? "0"
                            ).font(.statusFont).bold()
                        } else {
                            Text("?").font(.statusFont).bold()
                        }
                        Text(NSLocalizedString(" U", comment: "Insulin unit")).font(.statusFont).foregroundStyle(.secondary)
                    }.offset(x: 0, y: 5)
                }
            }
            .offset(y: 5)
        }

        var preview: some View {
            addBackground()
                .frame(minHeight: 200)
                .overlay {
                    PreviewChart(readings: $state.readings, lowLimit: $state.data.lowGlucose, highLimit: $state.data.highGlucose)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
                .blur(radius: animateTIRView ? 2 : 0)
                .onTapGesture {
                    timeIsNowTIR()
                    state.showModal(for: .statistics)
                }
                .overlay {
                    if animateTIRView {
                        animation.asAny()
                    }
                }
        }

        var infoPanelView: some View {
            addBackground()
                .frame(height: 30)
                .overlay {
                    HStack {
                        info
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
        }

        var activeIOBView: some View {
            addBackground()
                .frame(minHeight: 405)
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
                .addShadows()
                .padding(.horizontal, 10)
        }

        var activeCOBView: some View {
            addBackground()
                .frame(minHeight: 190)
                .overlay {
                    ActiveCOBView(data: $state.iobData)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
        }

        var loopPreview: some View {
            addBackground()
                .frame(minHeight: 160)
                .overlay {
                    LoopsView(loopStatistics: $state.loopStatistics)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
                .blur(radius: animateLoopView ? 2.5 : 0)
                .onTapGesture {
                    timeIsNowLoop()
                    state.showModal(for: .statistics)
                }
                .overlay {
                    if animateLoopView {
                        animation.asAny()
                    }
                }
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
                                        Text(shortened).font(.statusFont).foregroundStyle(.secondary)
                                    } else {
                                        Text(name).font(.statusFont).foregroundStyle(.secondary)
                                    }
                                }
                            } else { Text("📉") } // Hypo Treatment is not actually a preset
                        } else if override.percentage != 100 {
                            Text(override.percentage.formatted() + " %").font(.statusFont).foregroundStyle(.secondary)
                        } else if override.smbIsOff, !override.smbIsAlwaysOff {
                            Text("No ").font(.statusFont).foregroundStyle(.secondary) // "No" as in no SMBs
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

        func bolusProgressView(progress: Decimal, amount: Decimal) -> some View {
            ZStack {
                HStack {
                    VStack {
                        HStack {
                            Text("Bolusing")
                                .foregroundColor(.primary).font(.bolusProgressFont)
                            let bolused = targetFormatter.string(from: (amount * progress) as NSNumber) ?? ""

                            Text(
                                bolused + " " + NSLocalizedString("of", comment: "") + " " + amount
                                    .formatted() + NSLocalizedString(" U", comment: "")
                            ).font(.bolusProgressBarFont)
                        }
                        ProgressView(value: Double(progress))
                            .progressViewStyle(BolusProgressViewStyle())
                    }
                    Image(systemName: "xmark.square.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .font(.bolusProgressStopFont)
                        .onTapGesture { state.cancelBolus() }
                        .offset(x: 10, y: 0)
                }
            }
        }

        @ViewBuilder private func headerView(_ geo: GeometryProxy) -> some View {
            let height: CGFloat = displayGlucose ? 140 : 210
            addHeaderBackground()
                .frame(
                    height: fontSize < .extraExtraLarge ? height + geo.safeAreaInsets.top : height + 10 + geo
                        .safeAreaInsets.top
                )
                .overlay {
                    VStack {
                        ZStack {
                            if !displayGlucose {
                                glucoseView.frame(maxHeight: .infinity, alignment: .center).offset(y: -10)
                                loopView.frame(maxWidth: .infinity, alignment: .leading).offset(x: 40, y: -30)
                            }
                            if displayGlucose {
                                glucoseView.frame(maxHeight: .infinity, alignment: .center).offset(y: -10)
                            } else {
                                HStack {
                                    carbsAndInsulinView
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                    Spacer()
                                    pumpView
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                }
                                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 5)
                            }
                        }

                        if displayGlucose {
                            glucosePreview
                        } else {
                            infoPanelView
                        }

                        Divider()

                    }.padding(.top, geo.safeAreaInsets.top)
                }
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
                    (($0.glucose ?? 0) > veryHigh || Decimal($0.glucose ?? 0) < low) ? Color(.red) : Decimal($0.glucose ?? 0) >
                        high ? Color(.yellow) : Color(.darkGreen)
                )
                .symbolSize(5)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .chartYScale(
                domain: minimumRange * (state.data.units == .mmolL ? 0.0555 : 1.0) ... maximum *
                    (state.data.units == .mmolL ? 0.0555 : 1.0)
            )
            .chartXScale(
                domain: Date.now.addingTimeInterval(-1.days.timeInterval) ... Date.now
            )
            .frame(height: 50)
            .padding(.leading, 30)
            .padding(.trailing, 32)
            .padding(.top, 15)
            .dynamicTypeSize(DynamicTypeSize.medium ... DynamicTypeSize.large)
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
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .font(.timeSettingFont)
            .padding(.vertical, 15)
            .background(TimeEllipse(characters: string.count))
        }

        private var isfView: some View {
            ZStack {
                HStack {
                    Image(systemName: "divide").font(.system(size: 16)).foregroundStyle(.teal)
                    Text("\(state.data.suggestion?.sensitivityRatio ?? 1)").foregroundStyle(.primary)
                }
                .font(.timeSettingFont)
                .background(TimeEllipse(characters: 10))
                .onTapGesture {
                    if state.autoisf {
                        displayAutoHistory.toggle()
                    }
                }
            }.offset(x: 130)
        }

        private var animateLoopView: Bool {
            -1 * animateLoop.timeIntervalSinceNow < 1.5
        }

        private var animateTIRView: Bool {
            -1 * animateTIR.timeIntervalSinceNow < 1.5
        }

        private func timeIsNowLoop() {
            animateLoop = Date.now
        }

        private func timeIsNowTIR() {
            animateTIR = Date.now
        }

        private var animation: any View {
            ActivityIndicator(isAnimating: .constant(true), style: .large)
        }

        var body: some View {
            GeometryReader { geo in
                if onboarded.first?.firstRun ?? true, let openAPSSettings = state.openAPSSettings {
                    /// If old iAPS user pre v5.7.1 OpenAPS settings will be reset, but can be restored in View below
                    importResetSettingsView(settings: openAPSSettings)
                } else {
                    VStack(spacing: 0) {
                        // Header View
                        headerView(geo)
                        ScrollView {
                            VStack {
                                // Main Chart
                                chart
                                // Adjust hours visible (X-Axis) and optional ratio display
                                if state.extended {
                                    timeSetting
                                        .overlay { isfView }
                                } else {
                                    timeSetting
                                }
                                // TIR Chart
                                if !state.data.glucose.isEmpty {
                                    preview.padding(.top, 15)
                                }
                                // Loops Chart
                                loopPreview.padding(.vertical, 15)

                                if state.carbData > 0 {
                                    activeCOBView
                                }

                                // IOB Chart
                                if state.iobs > 0 {
                                    activeIOBView
                                }

                            }.background {
                                // Track vertical scroll
                                GeometryReader { proxy in
                                    let scrollPosition = proxy.frame(in: .named("HomeScrollView")).minY
                                    let yThreshold: CGFloat = -550
                                    Color.clear
                                        .onChange(of: scrollPosition) { y in
                                            if y < yThreshold, state.iobs > 0 || state.carbData > 0, !state.skipGlucoseChart {
                                                withAnimation(.easeOut(duration: 0.3)) { displayGlucose = true }
                                            } else {
                                                withAnimation(.easeOut(duration: 0.4)) { displayGlucose = false }
                                            }
                                        }
                                }
                            }
                        }.coordinateSpace(name: "HomeScrollView")
                        // Buttons
                        buttonPanel(geo)
                    }
                    .background(
                        colorScheme == .light ? .gray.opacity(IAPSconfig.backgroundOpacity * 2) : .white
                            .opacity(IAPSconfig.backgroundOpacity * 2)
                    )
                    .ignoresSafeArea(edges: .vertical)
                    .overlay {
                        if let progress = state.bolusProgress, let amount = state.bolusAmount {
                            ZStack {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(.gray.opacity(0.8))
                                    .frame(width: 320, height: 60)
                                bolusProgressView(progress: progress, amount: amount)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .offset(x: 0, y: -100)
                        }
                    }
                }
            }
            .onAppear {
                if onboarded.first?.firstRun ?? true {
                    state.fetchPreferences()
                }

                configureView()
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .sheet(isPresented: $displayAutoHistory) {
                AutoISFHistoryView(units: state.data.units)
            }
            .popup(isPresented: state.isStatusPopupPresented, alignment: .bottom, direction: .bottom) {
                popup
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.popUpGray)
                    )
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
        }

        private var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.statusTitle).font(.suggestionHeadline).foregroundColor(.white)
                    .padding(.bottom, 4)
                if let suggestion = state.data.suggestion {
                    TagCloudView(tags: suggestion.reasonParts).animation(.none, value: false)

                    Text(suggestion.reasonConclusion.capitalizingFirstLetter()).font(.suggestionSmallParts)
                        .foregroundColor(.white)
                } else {
                    Text("No sugestion found").font(.suggestionHeadline).foregroundColor(.white)
                }
                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Status at", comment: "") + " " + dateFormatter.string(from: date))
                        .foregroundColor(.white)
                        .font(.suggestionError)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.suggestionError).fontWeight(.semibold).foregroundColor(.orange)
                } else if let suggestion = state.data.suggestion, (suggestion.bg ?? 100) == 400 {
                    Text("Invalid CGM reading (HIGH).").font(.suggestionError).bold().foregroundColor(.loopRed).padding(.top, 8)
                    Text("SMBs and High Temps Disabled.").font(.suggestionParts).foregroundColor(.white).padding(.bottom, 4)
                }
            }
        }

        private func importResetSettingsView(settings: Preferences) -> some View {
            Restore.RootView(
                resolver: resolver,
                openAPS: settings
            )
        }
    }
}
