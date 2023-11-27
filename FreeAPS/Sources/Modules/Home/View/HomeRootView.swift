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

        let buttonFont = Font.custom("TimeButtonFont", size: 14)

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

        @ViewBuilder func status(_: GeometryProxy) -> some View {
            // HStack {
            pumpView
            // }
        }

        var cobIobView: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("IOB").font(.footnote).foregroundColor(.secondary)
                    Text(
                        (numberFormatter.string(from: (state.suggestion?.iob ?? 0) as NSNumber) ?? "0") +
                            NSLocalizedString(" U", comment: "Insulin unit")
                    )
                    .font(.footnote).fontWeight(.bold)
                }.frame(alignment: .top)
                HStack {
                    Text("COB").font(.footnote).foregroundColor(.secondary)
                    Text(
                        (numberFormatter.string(from: (state.suggestion?.cob ?? 0) as NSNumber) ?? "0") +
                            NSLocalizedString(" g", comment: "gram of carbs")
                    )
                    .font(.footnote).fontWeight(.bold)
                }.frame(alignment: .bottom)
            }
        }

        var cobIobView2: some View {
            HStack {
                Text("IOB").font(.callout).foregroundColor(.secondary)
                Text(
                    (numberFormatter.string(from: (state.suggestion?.iob ?? 0) as NSNumber) ?? "0") +
                        NSLocalizedString(" U", comment: "Insulin unit")
                )
                .font(.callout).fontWeight(.bold)

                Spacer()

                Text("COB").font(.callout).foregroundColor(.secondary)
                Text(
                    (numberFormatter.string(from: (state.suggestion?.cob ?? 0) as NSNumber) ?? "0") +
                        NSLocalizedString(" g", comment: "gram of carbs")
                )
                .font(.callout).fontWeight(.bold)

                Spacer()
            }
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
                state.isStatusPopupPresented = true
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

        var overrideString: String? {
            guard fetchedPercent.first?.enabled ?? false else {
                return nil
            }
            var percentString = "\((fetchedPercent.first?.percentage ?? 100).formatted(.number)) %"
            var target = (fetchedPercent.first?.target ?? 100) as Decimal
            let indefinite = (fetchedPercent.first?.indefinite ?? false)
            let unit = state.units.rawValue
            if state.units == .mmolL {
                target = target.asMmolL
            }
            var targetString = (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
            if tempTargetString != nil || target == 0 { targetString = "" }
            percentString = percentString == "100 %" ? "" : percentString

            let duration = (fetchedPercent.first?.duration ?? 0) as Decimal
            let addedMinutes = Int(duration)
            let date = fetchedPercent.first?.date ?? Date()
            var newDuration: Decimal = 0

            if date.addingTimeInterval(addedMinutes.minutes.timeInterval) > Date() {
                newDuration = Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes)
            }

            var durationString = indefinite ?
                "" : newDuration >= 1 ?
                (newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + " min") :
                (
                    newDuration > 0 ? (
                        (newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + " s"
                    ) :
                        ""
                )

            let smbToggleString = (fetchedPercent.first?.smbIsOff ?? false) ? " \u{20e0}" : ""
            var comma1 = ", "
            var comma2 = comma1
            var comma3 = comma1
            if targetString == "" || percentString == "" { comma1 = "" }
            if durationString == "" { comma2 = "" }
            if smbToggleString == "" { comma3 = "" }

            if percentString == "", targetString == "" {
                comma1 = ""
                comma2 = ""
            }
            if percentString == "", targetString == "", smbToggleString == "" {
                durationString = ""
                comma1 = ""
                comma2 = ""
                comma3 = ""
            }
            if durationString == "" {
                comma2 = ""
            }
            if smbToggleString == "" {
                comma3 = ""
            }

            if durationString == "", !indefinite {
                return nil
            }
            return percentString + comma1 + targetString + comma2 + durationString + comma3 + smbToggleString
        }

        var infoPanel: some View {
            HStack(alignment: .center) {
                if state.pumpSuspended {
                    Text("Pump suspended")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.loopGray)
                        .padding(.leading, 8)
                } else if let tempBasalString = tempBasalString {
                    Text(tempBasalString)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.insulin)
                        .padding(.leading, 8)
                }
                if state.tins {
                    Text(
                        "TINS: \(state.calculateTINS())" +
                            NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                    )
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.insulin)
                }

                if let tempTargetString = tempTargetString {
                    Text(tempTargetString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let overrideString = overrideString {
                    HStack {
                        Text("👤 " + overrideString)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .alert(
                        "Return to Normal?", isPresented: $showCancelAlert,
                        actions: {
                            Button("No", role: .cancel) {}
                            Button("Yes", role: .destructive) {
                                state.cancelProfile()
                            }
                        }, message: { Text("This will change settings back to your normal profile.") }
                    )
                    .padding(.trailing, 8)
                    .onTapGesture {
                        showCancelAlert = true
                    }
                }

                if state.closedLoop, state.settingsManager.preferences.maxIOB == 0 {
                    Text("Max IOB: 0").font(.callout).foregroundColor(.orange).padding(.trailing, 20)
                }

                if let progress = state.bolusProgress {
                    HStack {
                        Text("Bolusing")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                        ProgressView(value: Double(progress))
                            .progressViewStyle(BolusProgressViewStyle())
                            .padding(.trailing, 8)
                    }
                    .onTapGesture {
                        state.cancelBolus()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
        }

        var timeInterval: some View {
            HStack {
                ForEach(timeButtons) { button in
                    Text(button.active ? NSLocalizedString(button.label, comment: "") : button.number).onTapGesture {
                        state.hours = button.hours
                        highlightButtons()
                    }
                    .foregroundStyle(button.active ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.9) : .secondary)
                    .frame(maxHeight: 30).padding(.horizontal, 8)
                    .background(
                        button.active ?
                            // RGB(30, 60, 95)
                            (
                                colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                    Color.white
                            ) :
                            Color
                            .clear
                    )
                    .cornerRadius(20)
                }
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33),
                radius: colorScheme == .dark ? 5 : 3
            )
            .font(buttonFont)
        }

        var legendPanel: some View {
            ZStack {
                HStack(alignment: .center) {
                    Spacer()

                    Group {
                        Circle().fill(Color.loopGreen).frame(width: 8, height: 8)
                        Text("BG")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.loopGreen)
                    }
                    Group {
                        Circle().fill(Color.insulin).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("IOB")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                    }
                    Group {
                        Circle().fill(Color.zt).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("ZT")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.zt)
                    }
                    Group {
                        Circle().fill(Color.loopYellow).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("COB")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.loopYellow)
                    }
                    Group {
                        Circle().fill(Color.uam).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("UAM")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.uam)
                    }

                    if let eventualBG = state.eventualBG {
                        Text(
                            "⇢ " + numberFormatter.string(
                                from: (state.units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
                            )!
                        )
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
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
            .padding(.bottom)
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

        @ViewBuilder private func bottomPanel(_: GeometryProxy) -> some View {
            let colorRectangle: Color = colorScheme == .dark ? Color(
                red: 0.05490196078,
                green: 0.05490196078,
                blue: 0.05490196078
            ) : Color.white
            let colorIcon: Color = (colorScheme == .dark ? Color.white : Color.black).opacity(0.9)
            ZStack {
                Rectangle()
                    .fill(colorRectangle)
                    .frame(height: UIScreen.main.bounds.height / 13)
                    .cornerRadius(15)
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.75) : Color.black.opacity(0.33),
                        radius: colorScheme == .dark ? 5 : 3
                    )
                    .padding([.leading, .trailing], 10)

                HStack {
                    Button { state.showModal(for: .addCarbs(editMode: false, override: false)) }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image("carbs")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(colorIcon)
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
                    Button { state.showModal(for: .addTempTarget) }
                    label: {
                        Image("target")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
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
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
                    Spacer()
                    if state.allowManualTemp {
                        Button { state.showModal(for: .manualTempBasal) }
                        label: {
                            Image("bolus1")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .padding(8)
                        }
                        .foregroundColor(colorIcon)
                        .buttonStyle(.borderless)
                        Spacer()
                    }

                    // MARK: CANCEL OF PROFILE HAS TO BE IMPLEMENTED

                    // MAYBE WITH A SMALL INDICATOR AT THE SYMBOL
                    Button {
                        state.showModal(for: .overrideProfilesConfig)
                    } label: {
                        Image(systemName: "person")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
                    Spacer()
                    Button { state.showModal(for: .statistics)
                    }
                    label: {
                        Image(systemName: "chart.xyaxis.line")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
                    Spacer()
                    Button { state.showModal(for: .settings) }
                    label: {
                        Image("settings1")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }

        var body: some View {
            let colorBackground = colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    // RGB(3, 15, 28)
                    Color(red: 0.011, green: 0.058, blue: 0.109),
                    // RGB(10, 34, 55)
                    Color(red: 0.03921568627, green: 0.1333333333, blue: 0.2156862745)
                ]),
                startPoint: .bottom,
                endPoint: .top
            )
                :
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.1)]), startPoint: .top, endPoint: .bottom)
            let colourChart: Color = colorScheme == .dark ? Color(
                red: 0.05490196078,
                green: 0.05490196078,
                blue: 0.05490196078
            ) : .white

            GeometryReader { geo in
                VStack(spacing: 0) {
                    loopView.padding(.horizontal, 10)

                    Spacer()

                    glucoseView.padding(.top, 10).padding(.bottom, 20)

                    Spacer()

                    RoundedRectangle(cornerRadius: 15)
                        .fill(colourChart)
                        .overlay(status(geo))
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .shadow(
                            color: colorScheme == .dark ? Color.black.opacity(0.75) : Color.black.opacity(0.33),
                            radius: colorScheme == .dark ? 5 : 3
                        )
                        .padding(.horizontal, 10)
                        .frame(maxHeight: 40)

                    Spacer()

                    infoPanel
                        .padding(.horizontal, 10)

                    RoundedRectangle(cornerRadius: 15)
                        .fill(colourChart)
                        .overlay(mainChart)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .shadow(
                            color: colorScheme == .dark ? Color.black.opacity(0.75) : Color.black.opacity(0.33),
                            radius: colorScheme == .dark ? 5 : 3
                        )
                        .padding(.horizontal, 10)
                        .frame(maxHeight: UIScreen.main.bounds.height / 2.2)

                    Spacer()

                    legendPanel

                    Spacer()

                    timeInterval.padding(.bottom, 20)

                    Spacer()

                    bottomPanel(geo)
                }
                .background(colorBackground)
                .edgesIgnoringSafeArea([.horizontal, .bottom])
            }
            .onAppear {
                configureView {
                    highlightButtons()
                }
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .popup(isPresented: state.isStatusPopupPresented, alignment: .top, direction: .top) {
                popup
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(colorScheme == .dark ? Color(
                                red: 0.05490196078,
                                green: 0.05490196078,
                                blue: 0.05490196078
                            ) : Color(UIColor.darkGray))
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
                Text(state.statusTitle).font(.headline).foregroundColor(.white)
                    .padding(.bottom, 4)
                if let suggestion = state.suggestion {
                    TagCloudView(tags: suggestion.reasonParts).animation(.none, value: false)

                    Text(suggestion.reasonConclusion.capitalizingFirstLetter()).font(.caption).foregroundColor(.white)

                } else {
                    Text("No sugestion found").font(.body).foregroundColor(.white)
                }

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Error at", comment: "") + " " + dateFormatter.string(from: date))
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.caption).foregroundColor(.loopRed)
                } else if let suggestion = state.suggestion, (suggestion.bg ?? 100) == 400 {
                    Text("Invalid CGM reading (HIGH).").font(.callout).bold().foregroundColor(.loopRed).padding(.top, 8)
                    Text("SMBs and High Temps Disabled.").font(.caption).foregroundColor(.white).padding(.bottom, 4)
                }
            }
        }
    }
}
