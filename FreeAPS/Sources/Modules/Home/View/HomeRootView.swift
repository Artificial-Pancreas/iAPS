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

        struct Buttons: Identifiable {
            let label: String
            let number: String
            var active: Bool
            let hours: Int16
            var id: String { label }
        }

        @State var timeButtons: [Buttons] = [
            Buttons(label: "2 hours", number: "2", active: false, hours: 2),
            Buttons(label: "4 hours", number: "4", active: false, hours: 4),
            Buttons(label: "6 hours", number: "6", active: false, hours: 6),
            Buttons(label: "12 hours", number: "12", active: false, hours: 12),
            Buttons(label: "24 hours", number: "24", active: false, hours: 24)
        ]

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
                highGlucose: $state.highGlucose
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
            let target = tempTarget.targetBottom ?? 0
            let unitString = targetFormatter.string(from: (tempTarget.targetBottom?.asMmolL ?? 0) as NSNumber) ?? ""
            let rawString = (tirFormatter.string(from: (tempTarget.targetBottom ?? 0) as NSNumber) ?? "") + " " + state.units
                .rawValue

            var string = ""
            if sliderTTpresets.first?.active ?? false {
                let hbt = sliderTTpresets.first?.hbt ?? 0
                string = ", " + (tirFormatter.string(from: state.infoPanelTTPercentage(hbt, target) as NSNumber) ?? "") + " %"
            }

            let percentString = state
                .units == .mmolL ? (unitString + " mmol/L" + string) : (rawString + (string == "0" ? "" : string))
            return tempTarget.displayName + " " + percentString
        }

        func overrideString() -> Text? {
            if let override = fetchedPercent.first, override.enabled {
                if let profile = fetchedProfiles.filter({ $0.id == override.id }).first, profile.name != "" {
                    return Text(profile.name ?? "")
                } else if override.smbIsAlwaysOff {
                    return Text("💉").strikethrough(color: .red).bold()
                } else if override.smbIsOff {
                    return Text("🕝 💉")
                } else if override.percentage != 100 {
                    return Text("\(override.percentage.formatted(.number)) %")
                } else {
                    return Text("👤").foregroundColor(.purple)
                }
            }
            return nil
        }

        var infoPanel: some View {
            HStack(spacing: 10) {
                if state.pumpSuspended {
                    Text("Pump suspended")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.loopGray)
                        .padding(.leading, 8)
                } else if let tempBasalString = tempBasalString {
                    Text(tempBasalString)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .primary : .insulin)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                }

                if state.closedLoop, state.settingsManager.preferences.maxIOB == 0 {
                    Text("Check Max IOB Setting").font(.extraSmall).foregroundColor(.orange)
                } else if let tempTargetString = tempTargetString {
                    Text(tempTargetString)
                        .font(.buttonFont)
                        .foregroundColor(.secondary)
                }

                if let override = fetchedPercent.first, override.enabled {
                    if let profile = fetchedProfiles.filter({ $0.id == override.id }).first, profile.name != "" {
                        Text(profile.name ?? "")
                    } else if override.smbIsOff,!override.smbIsAlwaysOff {
                        Text("💉").strikethrough(color: .red).bold()
                    } else if override.smbIsOff {
                        Text("🕝 💉")
                    } else if override.percentage != 100 {
                        Text("\(override.percentage.formatted(.number)) %")
                    } else {
                        Text("👤").foregroundColor(.purple)
                    }
                }

                if let eventualBG = state.eventualBG {
                    HStack {
                        Image(systemName: "arrow.forward")
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
            .frame(maxWidth: .infinity, maxHeight: 30, alignment: .bottom)
        }

        var timeInterval: some View {
            HStack {
                ForEach(timeButtons) { button in
                    Text(button.active ? NSLocalizedString(button.label, comment: "") : button.number).onTapGesture {
                        state.hours = button.hours
                    }
                    .foregroundStyle(button.active ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.9) : .secondary)
                    .frame(maxHeight: 40).padding(8)
                    .background(
                        button.active ?
                            (colorScheme == .dark ? .blueComplicationBackground : Color.white) : Color.clear
                    )
                    .cornerRadius(20)
                }
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33),
                radius: colorScheme == .dark ? 5 : 3
            )
            .font(.buttonFont)
            .onChange(of: state.hours) { _ in
                highlightButtons()
            }
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
                    thresholdLines: $state.thresholdLines
                )
            }
            .padding(.bottom, 5)
            .modal(for: .dataTable, from: self)
        }

        private func selectedProfile() -> (name: String, isOn: Bool) {
            var profileString = ""
            var display: Bool = false

            let duration = (fetchedPercent.first?.duration ?? 0) as Decimal
            let indefinite = fetchedPercent.first?.indefinite ?? false
            let addedMinutes = Int(duration)
            let date = fetchedPercent.first?.date ?? Date()
            if date.addingTimeInterval(addedMinutes.minutes.timeInterval) > Date() || indefinite {
                display.toggle()
            }

            if fetchedPercent.first?.enabled ?? false, !(fetchedPercent.first?.isPreset ?? false), display {
                profileString = NSLocalizedString("Custom Profile", comment: "Custom but unsaved Profile")
            } else if !(fetchedPercent.first?.enabled ?? false) || !display {
                profileString = NSLocalizedString("Normal Profile", comment: "Your normal Profile. Use a short string")
            } else {
                let id_ = fetchedPercent.first?.id ?? ""
                let profile = fetchedProfiles.filter({ $0.id == id_ }).first
                if profile != nil {
                    profileString = profile?.name?.description ?? ""
                }
            }
            return (name: profileString, isOn: display)
        }

        func highlightButtons() {
            for i in 0 ..< timeButtons.count {
                timeButtons[i].active = timeButtons[i].hours == state.hours
            }
        }

        @ViewBuilder private func buttonPanel(_ geo: GeometryProxy) -> some View {
            ZStack {
                Rectangle().fill(.gray.opacity(IAPSconfig.backgroundOpacity)).frame(height: 50 + geo.safeAreaInsets.bottom)
                let isOverride = fetchedPercent.first?.enabled ?? false
                HStack {
                    Button { state.showModal(for: .dataTable) }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image(systemName: "book.pages")
                                .symbolRenderingMode(.hierarchical)
                                .resizable()
                                .frame(width: IAPSconfig.buttonSize, height: IAPSconfig.buttonSize, alignment: .bottom)
                                .foregroundColor(.secondary)
                                .padding(8)
                        }
                    }.buttonStyle(.borderless)
                    Spacer()
                    Button { state.showModal(for: .addCarbs(editMode: false, override: false)) }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image(systemName: "fork.knife")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: IAPSconfig.buttonSize, height: IAPSconfig.buttonSize, alignment: .bottom)
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
                            state.cancelProfile()
                        } else {
                            state.showModal(for: .overrideProfilesConfig)
                        }
                    }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image(systemName: "person.fill")
                                .symbolRenderingMode(.palette)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.purple)
                                .frame(height: IAPSconfig.buttonSize, alignment: .bottom)
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
                // .frame(height: UIScreen.main.bounds.height / 11.5)
                // .background(.gray.opacity(IAPSconfig.backgroundOpacity))
            }
        }

        var loop: some View {
            addBackground()
                .frame(maxWidth: UIScreen.main.bounds.width / 3, maxHeight: 35)
                .overlay(loopView)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                // .padding(.bottom, 10)
                .onTapGesture {
                    state.isStatusPopupPresented = true
                }.onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.runLoop()
                }
        }

        var pumpStatus: some View {
            addBackground()
                .frame(maxWidth: UIScreen.main.bounds.width / 2, maxHeight: 35)
                .overlay(pumpView)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .addShadows()
                .padding(.horizontal, 10)
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
                    minHeight: !state.displayTimeButtons ? UIScreen.main.bounds.height / 1.65 : UIScreen.main.bounds
                        .height / 1.87
                )
                .addShadows()
        }

        var carbsAndInsulinView: some View {
            HStack(spacing: 10) {
                if let settings = state.settingsManager {
                    let opacity: CGFloat = colorScheme == .dark ? 0.2 : 0.25
                    let materialOpacity: CGFloat = 0.25
                    HStack {
                        let substance = Double(state.suggestion?.cob ?? 0)
                        let max = max(Double(settings.preferences.maxCOB), 1)
                        let fraction: Double = 1 - (substance / max)
                        let fill = CGFloat(min(Swift.max(fraction, 0.10), substance > 0 ? 0.85 : 0.92))
                        UnevenRoundedRectangle.testTube
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        Gradient.Stop(color: .white.opacity(opacity), location: fill),
                                        Gradient.Stop(color: .loopYellow, location: fill)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            ).overlay { FrostedGlass(opacity: materialOpacity) }
                            .frame(width: 12, height: 45)
                            .offset(x: 0, y: -10)
                            .glassShadows()
                        HStack(spacing: 0) {
                            Text(
                                numberFormatter.string(from: (state.suggestion?.cob ?? 0) as NSNumber) ?? "0"
                            ).font(.statusFont).bold()
                            Text(NSLocalizedString(" g", comment: "gram of carbs")).font(.statusFont).foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        let substance = Double(state.suggestion?.iob ?? 0)
                        let max = max(Double(settings.preferences.maxIOB), 1)
                        let fraction: Double = 1 - (substance / max)
                        let fill = CGFloat(min(Swift.max(fraction, 0.10), substance > 0 ? 0.85 : 0.92))
                        UnevenRoundedRectangle.testTube
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        Gradient.Stop(color: .white.opacity(opacity), location: fill),
                                        Gradient.Stop(color: .insulin, location: fill)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            ).overlay { FrostedGlass(opacity: materialOpacity) }
                            .frame(width: 10, height: 35)
                            .offset(x: 0, y: -4)
                            .glassShadows()
                        HStack(spacing: 0) {
                            Text(
                                numberFormatter.string(from: (state.suggestion?.iob ?? 0) as NSNumber) ?? "0"
                            ).font(.statusFont).bold()
                            Text(NSLocalizedString(" U", comment: "Insulin unit")).font(.statusFont).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        var isfView: some View {
            HStack {
                if let suggestion = state.suggestion {
                    // Image(systemName: "arrow.down").foregroundStyle(Color.insulin)
                    Text("ISF").font(.statusFont).foregroundStyle(.secondary)
                    let isf = fetchedTargetFormatter.string(from: (suggestion.isf ?? 0) as NSNumber) ?? ""
                    Text(isf)
                }
            }
        }

        var preview: some View {
            addBackground()
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
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
            HStack {
                if let override = fetchedPercent.first {
                    if override.enabled {
                        if override.isPreset {
                            let profile = fetchedProfiles.first(where: { $0.id == override.id })
                            if let currentProfile = profile {
                                if let name = currentProfile.name, name != "EMPTY", name.nonEmpty != nil, name != "",
                                   name != "\u{0022}\u{0022}"
                                {
                                    Text(name).font(.statusFont)
                                }
                            }
                        } else {
                            Text(override.percentage.formatted() + " %")
                        }
                    }
                }
            }
        }

        func bolusProgressView(progress: Decimal) -> some View {
            HStack {
                Text("Bolusing")
                    .foregroundColor(.primary)
                ProgressView(value: Double(progress))
                    .progressViewStyle(BolusProgressViewStyle())
                Image(systemName: "x.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
            }.font(.system(size: 16, weight: .bold))
                .onTapGesture {
                    state.cancelBolus()
                }
        }

        @ViewBuilder private func headerView(_: GeometryProxy) -> some View {
            addHeaderBackground()
                .frame(minHeight: 155)
                .overlay {
                    VStack {
                        ZStack {
                            glucoseView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            loopView.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 5)
                            carbsAndInsulinView
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                .padding(.leading, 7)
                            pumpView
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(.trailing, 7).padding(.bottom, 5)
                        }.padding(.top, 50) // .padding(.bottom, 10)
                    }
                }
                .clipShape(Rectangle())
        }

        var body: some View {
            GeometryReader { geo in
                VStack {
                    ScrollView {
                        VStack(spacing: 10) {
                            headerView(geo)
                            chart
                            if state.displayTimeButtons {
                                timeInterval.padding(.bottom, 20)
                            }
                            if let progress = state.bolusProgress {
                                bolusProgressView(progress: progress)
                            }
                            preview
                        }
                    }
                    .scrollIndicators(.hidden)
                    buttonPanel(geo)
                }
                .background(.gray.opacity(IAPSconfig.backgroundOpacity))
                .edgesIgnoringSafeArea(.vertical)
            }
            .onAppear { configureView { highlightButtons() } }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .popup(isPresented: state.isStatusPopupPresented, alignment: .bottom, direction: .bottom) {
                popup
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(UIColor.darkGray))
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
