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
        @State var scrollOffset = CGFloat.zero
        @State var display = false

        @Namespace var scrollSpace

        let scrollAmount: CGFloat = 290
        let buttonFont = Font.custom("TimeButtonFont", size: 14)

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

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var fetchedTargetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
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
                timerDate: $state.timerDate,
                delta: $state.glucoseDelta,
                units: $state.units,
                alarm: $state.alarm,
                lowGlucose: $state.lowGlucose,
                highGlucose: $state.highGlucose,
                alwaysUseColors: $state.alwaysUseColors
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
                timerDate: $state.timerDate, timeZone: $state.timeZone,
                state: state
            )
            .onTapGesture {
                if state.pumpDisplayState != nil {
                    state.setupPump = true
                }
            }
        }

        var loopView: some View {
            LoopView(
                suggestion: $state.suggestion,
                enactedSuggestion: $state.enactedSuggestion,
                closedLoop: $state.closedLoop,
                timerDate: $state.timerDate,
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

        var info: some View {
            HStack(spacing: 10) {
                ZStack {
                    HStack {
                        if state.pumpSuspended {
                            Text("Pump suspended")
                                .font(.extraSmall).bold().foregroundColor(.loopGray)
                        } else if let tempBasalString = tempBasalString {
                            Text(tempBasalString)
                                .font(.statusFont).bold()
                                .foregroundColor(.insulin)
                        }
                        if state.closedLoop, state.settingsManager.preferences.maxIOB == 0 {
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
                    if let eventualBG = state.eventualBG {
                        HStack {
                            Text("⇢").font(.statusFont).foregroundStyle(.secondary)

                            // Image(systemName: "arrow.forward")
                            Text(
                                fetchedTargetFormatter.string(
                                    from: (state.units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
                                )!
                            ).font(.statusFont).foregroundColor(colorScheme == .dark ? .white : .black)
                            Text(state.units.rawValue).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                    }
                }
            }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }

        var infoPanel: some View {
            info
                .frame(minHeight: 35, maxHeight: 35)
        }

        var mainChart: some View {
            ZStack {
                if state.animatedBackground {
                    SpriteView(scene: spriteScene, options: [.allowsTransparency])
                        .ignoresSafeArea()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
                MainChartView(
                    glucose: $state.glucose,
                    isManual: $state.isManual,
                    suggestion: $state.suggestion,
                    tempBasals: $state.tempBasals,
                    boluses: $state.boluses,
                    suspensions: $state.suspensions,
                    announcement: $state.announcement,
                    hours: .constant(state.filteredHours),
                    maxBasal: $state.maxBasal,
                    autotunedBasalProfile: $state.autotunedBasalProfile,
                    basalProfile: $state.basalProfile,
                    tempTargets: $state.tempTargets,
                    carbs: $state.carbs,
                    timerDate: $state.timerDate,
                    units: $state.units,
                    smooth: $state.smooth,
                    highGlucose: $state.highGlucose,
                    lowGlucose: $state.lowGlucose,
                    screenHours: $state.hours,
                    displayXgridLines: $state.displayXgridLines,
                    displayYgridLines: $state.displayYgridLines,
                    thresholdLines: $state.thresholdLines,
                    triggerUpdate: $triggerUpdate,
                    overrideHistory: $state.overrideHistory,
                    minimumSMB: $state.minimumSMB,
                    maxBolus: $state.maxBolus,
                    maxBolusValue: $state.maxBolusValue, useInsulinBars: $state.useInsulinBars
                )
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
        }

        var chart: some View {
            let ratio = state.timeSettings ? 1.61 : 1.44
            let ratio2 = state.timeSettings ? 1.65 : 1.51

            return addColouredBackground()
                .overlay {
                    VStack(spacing: 0) {
                        infoPanel
                        mainChart
                    }
                }
                .frame(minHeight: UIScreen.main.bounds.height / (fontSize < .extraExtraLarge ? ratio : ratio2))
        }

        var carbsAndInsulinView: some View {
            HStack {
                if let settings = state.settingsManager {
                    let opacity: CGFloat = colorScheme == .dark ? 0.2 : 0.6
                    let materialOpacity: CGFloat = colorScheme == .dark ? 0.25 : 0.10
                    HStack {
                        let substance = Double(state.suggestion?.cob ?? 0)
                        let max = max(Double(settings.preferences.maxCOB), 1)
                        let fraction: Double = 1 - (substance / max)
                        let fill = CGFloat(min(Swift.max(fraction, 0.05), substance > 0 ? 0.92 : 0.97))
                        TestTube(
                            opacity: opacity,
                            amount: fill,
                            colourOfSubstance: .loopYellow,
                            materialOpacity: materialOpacity
                        )
                        .frame(width: 12, height: 38)
                        .offset(x: 0, y: -5)
                        HStack(spacing: 0) {
                            Text(
                                numberFormatter.string(from: (state.suggestion?.cob ?? 0) as NSNumber) ?? "0"
                            ).font(.statusFont).bold()
                            Text(NSLocalizedString(" g", comment: "gram of carbs")).font(.statusFont).foregroundStyle(.secondary)
                        }.offset(x: 0, y: 5)
                    }
                    HStack {
                        let substance = Double(state.suggestion?.iob ?? 0)
                        let max = max(Double(settings.preferences.maxIOB), 1)
                        let fraction: Double = 1 - (substance / max)
                        let fill = CGFloat(min(Swift.max(fraction, 0.05), substance > 0 ? 0.92 : 0.98))
                        TestTube(
                            opacity: opacity,
                            amount: fill,
                            colourOfSubstance: substance < 0 ? .red : .insulin,
                            materialOpacity: materialOpacity
                        )
                        .frame(width: 12, height: 38)
                        .offset(x: 0, y: -5)
                        HStack(spacing: 0) {
                            Text(
                                numberFormatter.string(from: (state.suggestion?.iob ?? 0) as NSNumber) ?? "0"
                            ).font(.statusFont).bold()
                            Text(NSLocalizedString(" U", comment: "Insulin unit")).font(.statusFont).foregroundStyle(.secondary)
                        }.offset(x: 0, y: 5)
                    }
                }
            }
        }

        var preview: some View {
            addBackground()
                .frame(minHeight: 200)
                .overlay {
                    PreviewChart(readings: $state.readings, lowLimit: $state.lowGlucose, highLimit: $state.highGlucose)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
                .onTapGesture {
                    state.showModal(for: .statistics)
                }
        }

        var activeIOBView: some View {
            addBackground()
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
                .addShadows()
                .padding(.horizontal, 10)
        }

        var activeCOBView: some View {
            addBackground()
                .frame(minHeight: 230)
                .overlay {
                    ActiveCOBView(data: $state.iobData)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
        }

        var loopPreview: some View {
            addBackground()
                .frame(minHeight: 190)
                .overlay {
                    LoopsView(loopStatistics: $state.loopStatistics)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
                .onTapGesture {
                    state.showModal(for: .statistics)
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
                            }
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
            addHeaderBackground()
                .frame(
                    maxHeight: fontSize < .extraExtraLarge ? 125 + geo.safeAreaInsets.top : 135 + geo
                        .safeAreaInsets.top
                )
                .overlay {
                    VStack {
                        ZStack {
                            glucoseView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 10)
                            HStack {
                                carbsAndInsulinView
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                Spacer()
                                loopView.frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 3)
                                    .offset(x: -2, y: 0) // To do: Remove all offsets, if possible.
                                Spacer()
                                pumpView
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                    .padding(.bottom, 2)
                            }
                            .dynamicTypeSize(...DynamicTypeSize.xLarge)
                            .padding(.horizontal, 10)
                        }
                    }.padding(.top, geo.safeAreaInsets.top).padding(.bottom, 10)
                }
                .clipShape(Rectangle())
        }

        @ViewBuilder private func glucoseHeaderView() -> some View {
            addHeaderBackground()
                .frame(maxHeight: 90)
                .overlay {
                    VStack {
                        ZStack {
                            glucosePreview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .dynamicTypeSize(...DynamicTypeSize.medium)
                        }
                    }
                }
                .clipShape(Rectangle())
        }

        var glucosePreview: some View {
            let data = state.glucose
            let minimum = data.compactMap(\.glucose).min() ?? 0
            let minimumRange = Double(minimum) * 0.8
            let maximum = Double(data.compactMap(\.glucose).max() ?? 0) * 1.1

            let high = state.highGlucose
            let low = state.lowGlucose
            let veryHigh = 198

            return Chart(data) {
                PointMark(
                    x: .value("Time", $0.dateString),
                    y: .value("Glucose", Double($0.glucose ?? 0) * (state.units == .mmolL ? 0.0555 : 1.0))
                )
                .foregroundStyle(
                    (($0.glucose ?? 0) > veryHigh || Decimal($0.glucose ?? 0) < low) ? Color(.red) : Decimal($0.glucose ?? 0) >
                        high ? Color(.yellow) : Color(.darkGreen)
                )
                .symbolSize(7)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisValueLabel(
                        format: .dateTime.hour(.defaultDigits(amPM: .omitted))
                            .locale(Locale(identifier: "sv"))
                    )
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .chartYScale(
                domain: minimumRange * (state.units == .mmolL ? 0.0555 : 1.0) ... maximum * (state.units == .mmolL ? 0.0555 : 1.0)
            )
            .chartXScale(
                domain: Date.now.addingTimeInterval(-1.days.timeInterval) ... Date.now
            )
            .frame(maxHeight: 70)
            .padding(.leading, 30)
            .padding(.trailing, 32)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }

        var timeSetting: some View {
            let string = "\(state.hours) " + NSLocalizedString("hours", comment: "") + "   "
            return Menu(string) {
                Button("3 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 3 })
                Button("6 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 6 })
                Button("12 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 12 })
                Button("24 " + NSLocalizedString("hours", comment: ""), action: { state.hours = 24 })
                Button("UI/UX Settings", action: { state.showModal(for: .statisticsConfig) })
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colorScheme == .dark ? .primary : Color(.darkGray))
            .font(.timeSettingFont)
            .padding(.vertical, 15)
            .background(TimeEllipse(characters: string.count))
        }

        var body: some View {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    headerView(geo)
                    if !state.skipGlucoseChart, scrollOffset > scrollAmount {
                        glucoseHeaderView()
                            .transition(.move(edge: .top))
                    }

                    ScrollView {
                        ScrollViewReader { _ in
                            LazyVStack {
                                chart
                                if state.timeSettings { timeSetting }
                                preview.padding(.top, state.timeSettings ? 5 : 15)
                                loopPreview.padding(.top, 15)
                                if state.iobData.count > 5 {
                                    activeCOBView.padding(.top, 15)
                                    activeIOBView.padding(.top, 15)
                                }
                            }
                            .background(GeometryReader { geo in
                                let offset = -geo.frame(in: .named(scrollSpace)).minY
                                Color.clear
                                    .preference(
                                        key: ScrollViewOffsetPreferenceKey.self,
                                        value: offset
                                    )
                            })
                        }
                    }
                    .onPreferenceChange(ScrollViewOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                        if !state.skipGlucoseChart, scrollOffset > scrollAmount {
                            display.toggle()
                        }
                    }
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
            .onAppear(perform: configureView)
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
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
            .onAppear(perform: configureView)
        }

        private var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.statusTitle).font(.suggestionHeadline).foregroundColor(.white)
                    .padding(.bottom, 4)
                if let suggestion = state.suggestion {
                    TagCloudView(tags: suggestion.reasonParts).animation(.none, value: false)

                    Text(suggestion.reasonConclusion.capitalizingFirstLetter()).font(.suggestionSmallParts)
                        .foregroundColor(.white)
                } else {
                    Text("No sugestion found").font(.suggestionHeadline).foregroundColor(.white)
                }
                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Error at", comment: "") + " " + dateFormatter.string(from: date))
                        .foregroundColor(.white)
                        .font(.suggestionError)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.buttonFont).foregroundColor(.loopRed)
                } else if let suggestion = state.suggestion, (suggestion.bg ?? 100) == 400 {
                    Text("Invalid CGM reading (HIGH).").font(.suggestionError).bold().foregroundColor(.loopRed).padding(.top, 8)
                    Text("SMBs and High Temps Disabled.").font(.suggestionParts).foregroundColor(.white).padding(.bottom, 4)
                }
            }
        }
    }
}
