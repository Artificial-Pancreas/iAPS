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
        @State var triggerUpdate = false

        @Environment(\.managedObjectContext) var moc
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
                timerDate: $state.timerDate,
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
                    " - Manual Basal ⚠️",
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

        var infoPanel: some View {
            HStack(spacing: 10) {
                ZStack {
                    HStack {
                        if state.pumpSuspended {
                            Text("Pump suspended")
                                .font(.custom("TempBasal", fixedSize: 13)).bold().foregroundColor(.loopGray)
                        } else if let tempBasalString = tempBasalString {
                            Text(tempBasalString)
                                .font(.custom("TempBasal", fixedSize: 13)).bold()
                                .foregroundColor(.insulin)
                        }
                        if state.closedLoop, state.settingsManager.preferences.maxIOB == 0 {
                            Text("Check Max IOB Setting").font(.extraSmall).foregroundColor(.orange)
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
            }
            .frame(maxWidth: .infinity, maxHeight: 30, alignment: .bottom)
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
                    overrideHistory: $state.overrideHistory
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
                HStack {
                    Button { state.showModal(for: .dataTable) }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .leading, vertical: .bottom)) {
                            Image(systemName: "book")
                                .symbolRenderingMode(.hierarchical)
                                .resizable()
                                .frame(width: IAPSconfig.buttonSize, height: IAPSconfig.buttonSize, alignment: .bottom)
                                .foregroundColor(.gray)
                                .padding(8)
                        }
                    }.buttonStyle(.borderless)
                    Spacer()
                    Button { state.showModal(for: .addCarbs(editMode: false, override: false)) }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image("carbs")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(colorScheme == .dark ? .loopYellow : .orange)
                                .padding(8)
                                .foregroundColor(.loopYellow)
                                .padding(8)
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
                        if isOverride {
                            showCancelAlert.toggle()
                            // state.cancelProfile()
                            // triggerUpdate.toggle()
                        } else {
                            state.showModal(for: .overrideProfilesConfig)
                        }
                    }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image(systemName: isOverride ? "person.fill" : "person")
                                .symbolRenderingMode(.palette)
                                .font(.custom("Buttons", size: 32))
                                .foregroundStyle(.purple)
                                .padding(8)
                                .background(isOverride ? .blue.opacity(0.3) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }.buttonStyle(.borderless)

                    if state.useTargetButton {
                        Spacer()
                        Button { state.showModal(for: .addTempTarget) }
                        label: {
                            Image("target")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: IAPSconfig.buttonSize, height: IAPSconfig.buttonSize)
                                .padding(8)
                        }
                        .foregroundColor(.loopGreen)
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    Button {
                        state.showModal(for: .bolus(
                            waitForSuggestion: true,
                            fetch: false
                        ))
                    }
                    label: {
                        Image("bolus")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: IAPSconfig.buttonSize, height: IAPSconfig.buttonSize, alignment: .bottom)
                            .padding(8)
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
                                .padding(8)
                        }
                        .foregroundColor(.insulin)
                        Spacer()
                    }
                    Button { state.showModal(for: .settings) }
                    label: {
                        Image("settings1")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: IAPSconfig.buttonSize, height: IAPSconfig.buttonSize, alignment: .bottom)
                            .padding(8)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.gray)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, geo.safeAreaInsets.bottom)
            }.alert(
                "Return to Normal?", isPresented: $showCancelAlert,
                actions: {
                    Button("No", role: .cancel) {}
                    Button("Yes", role: .destructive) {
                        state.cancelProfile()
                        triggerUpdate.toggle()
                    }
                }, message: { Text("This will change settings back to your normal profile.") }
            )
        }

        var chart: some View {
            addColouredBackground()
                .overlay {
                    VStack {
                        infoPanel
                        mainChart
                    }
                }
                .frame(
                    minHeight: UIScreen.main.bounds.height / 1.46
                )
        }

        var carbsAndInsulinView: some View {
            HStack(spacing: 10) {
                if let settings = state.settingsManager {
                    let opacity: CGFloat = colorScheme == .dark ? 0.2 : 0.6
                    let materialOpacity: CGFloat = colorScheme == .dark ? 0.25 : 0.10
                    HStack {
                        let substance = Double(state.suggestion?.cob ?? 0)
                        let max = max(Double(settings.preferences.maxCOB), 1)
                        let fraction: Double = 1 - (substance / max)
                        let fill = CGFloat(min(Swift.max(fraction, 0.10), substance > 0 ? 0.85 : 0.92))
                        TestTube(opacity: opacity, amount: fill, colourOfSubstance: .loopYellow, materialOpacity: materialOpacity)
                            .frame(width: 13.8, height: 40)
                            .offset(x: 0, y: -6)
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
                        let fill = CGFloat(min(Swift.max(fraction, 0.10), substance > 0 ? 0.85 : 0.92))
                        TestTube(opacity: opacity, amount: fill, colourOfSubstance: .insulin, materialOpacity: materialOpacity)
                            .frame(width: 11, height: 36)
                            .offset(x: 0, y: -2.5)
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
                .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    PreviewChart(readings: $state.readings, lowLimit: $state.lowGlucose, highLimit: $state.highGlucose)
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
                                    Text(name).font(.statusFont).foregroundStyle(.secondary)
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

        func bolusProgressView(progress: Decimal) -> some View {
            ZStack {
                HStack {
                    Text("Bolusing")
                        .foregroundColor(.primary).font(.bolusProgressFont)
                    ProgressView(value: Double(progress))
                        .progressViewStyle(BolusProgressViewStyle())
                    Image(systemName: "xmark.square.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .font(.bolusProgressStopFont)
                        .onTapGesture {
                            state.cancelBolus()
                        }
                }
            }
        }

        @ViewBuilder private func headerView(_ geo: GeometryProxy) -> some View {
            addHeaderBackground()
                .frame(minHeight: 120 + geo.safeAreaInsets.top)
                .overlay {
                    VStack {
                        ZStack {
                            glucoseView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 10)
                            loopView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 3)
                            carbsAndInsulinView
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                .padding(.leading, 10)
                            pumpView
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(.trailing, 7).padding(.bottom, 2)
                        }.padding(.top, geo.safeAreaInsets.top).padding(.bottom, 5)
                    }
                }
                .clipShape(Rectangle())
        }

        var body: some View {
            GeometryReader { geo in
                VStack {
                    ScrollView {
                        VStack(spacing: 0) {
                            headerView(geo)
                            RaisedRectangle()
                            chart
                            preview.padding(.top, 15)
                        }
                    }
                    .scrollIndicators(.hidden)
                    buttonPanel(geo)
                }
                .background(.gray.opacity(IAPSconfig.backgroundOpacity * 2))
                .edgesIgnoringSafeArea(.vertical)
                .overlay {
                    if let progress = state.bolusProgress {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.gray.opacity(0.8))
                                .frame(width: 300, height: 50)
                            bolusProgressView(progress: progress)
                        }.frame(maxWidth: .infinity, alignment: .center)
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
