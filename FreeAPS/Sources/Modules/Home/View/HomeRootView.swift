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
        @State var selectedState: durationState

        // Average/Median/Readings and CV/SD titles and values switches when you tap them
        @State var averageOrMedianTitle = NSLocalizedString("Average", comment: "")
        @State var median_ = ""
        @State var average_ = ""
        @State var readings = ""

        @State var averageOrmedian = ""
        @State var CV_or_SD_Title = NSLocalizedString("CV", comment: "CV")
        @State var cv_ = ""
        @State var sd_ = ""
        @State var CVorSD = ""
        // Switch between Loops and Errors when tapping in statPanel
        @State var loopStatTitle = NSLocalizedString("Loops", comment: "Nr of Loops in statPanel")

        @FetchRequest(
            entity: Override.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var fetchedPercent: FetchedResults<Override>

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

        @ViewBuilder func header(_ geo: GeometryProxy) -> some View {
            HStack(alignment: .bottom) {
                Spacer()
                cobIobView
                Spacer()
                glucoseView
                Spacer()
                pumpView
                Spacer()
                loopView
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, geo.safeAreaInsets.top)
            .padding(.bottom, 6)
            .background(Color.gray.opacity(0.2))
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

        var glucoseView: some View {
            CurrentGlucoseView(
                recentGlucose: $state.recentGlucose,
                delta: $state.glucoseDelta,
                units: $state.units,
                alarm: $state.alarm
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
                timerDate: $state.timerDate
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
            ).onTapGesture {
                isStatusPopupPresented = true
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
            return rateString + NSLocalizedString(" U/hr", comment: "Unit per hour with space") + manualBasalString
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
            } /* else if enactedSliderTT.first?.enabled ?? false {
                 let hbt = enactedSliderTT.first?.hbt ?? 0
                 string = ", " + (tirFormatter.string(from: state.infoPanelTTPercentage(hbt, target) as NSNumber) ?? "") + " %"
             } */

            let percentString = state
                .units == .mmolL ? (unitString + " mmol/L" + string) : (rawString + (string == "0" ? "" : string))
            return tempTarget.displayName + " " + percentString
        }

        var overrideString: String? {
            guard fetchedPercent.first?.enabled ?? false else {
                return nil
            }
            let percentString = "\((fetchedPercent.first?.percentage ?? 100).formatted(.number)) %"
            let durationString = (fetchedPercent.first?.indefinite ?? false) ?
                "" : ", " + (tirFormatter.string(from: (fetchedPercent.first?.duration ?? 0) as NSNumber) ?? "") + " min"

            return percentString + durationString
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

                if let tempTargetString = tempTargetString {
                    Text(tempTargetString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
                
                if let overrideString = overrideString {
                    Text(overrideString)
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .padding(.trailing, 8)
                }

                if let progress = state.bolusProgress {
                    Text("Bolusing")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                    ProgressView(value: Double(progress))
                        .progressViewStyle(BolusProgressViewStyle())
                        .padding(.trailing, 8)
                        .onTapGesture {
                            state.cancelBolus()
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
        }

        @ViewBuilder private func statPanel() -> some View {
            if state.displayStatistics {
                VStack(spacing: 8) {
                    durationButton(states: durationState.allCases, selectedState: $selectedState)

                    switch selectedState {
                    case .day:

                        let hba1c_all = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.total ?? 0) as NSNumber) ?? ""
                        let average_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Average.day ?? 0) as NSNumber) ?? ""
                        let median_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Median.day ?? 0) as NSNumber) ?? ""
                        let tir_low = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypos.day ?? 0) as NSNumber) ?? ""
                        let tir_high = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypers.day ?? 0) as NSNumber) ?? ""
                        let tir_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.TIR.day ?? 0) as NSNumber) ?? ""
                        let hba1c_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.day ?? 0) as NSNumber) ?? ""
                        let sd_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.Variance.SD.day ?? 0) as NSNumber) ?? ""
                        let cv_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Variance.CV.day ?? 0) as NSNumber) ?? ""

                        averageTIRhca1c(hba1c_all, average_, median_, tir_low, tir_high, tir_, hba1c_, sd_, cv_)

                    case .week:
                        let hba1c_all = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.total ?? 0) as NSNumber) ?? ""
                        let average_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Average.week ?? 0) as NSNumber) ?? ""
                        let median_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Median.week ?? 0) as NSNumber) ?? ""
                        let tir_low = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypos.week ?? 0) as NSNumber) ?? ""
                        let tir_high = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypers.week ?? 0) as NSNumber) ?? ""
                        let tir_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.TIR.week ?? 0) as NSNumber) ?? ""
                        let hba1c_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.week ?? 0) as NSNumber) ?? ""
                        let sd_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.Variance.SD.week ?? 0) as NSNumber) ?? ""
                        let cv_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Variance.CV.week ?? 0) as NSNumber) ?? ""

                        averageTIRhca1c(hba1c_all, average_, median_, tir_low, tir_high, tir_, hba1c_, sd_, cv_)

                    case .month:
                        let hba1c_all = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.total ?? 0) as NSNumber) ?? ""
                        let average_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Average.month ?? 0) as NSNumber) ?? ""
                        let median_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Median.month ?? 0) as NSNumber) ?? ""
                        let tir_low = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypos.month ?? 0) as NSNumber) ?? ""
                        let tir_high = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypers.month ?? 0) as NSNumber) ?? ""
                        let tir_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.TIR.month ?? 0) as NSNumber) ?? ""
                        let hba1c_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.month ?? 0) as NSNumber) ?? ""
                        let sd_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.Variance.SD.month ?? 0) as NSNumber) ?? ""
                        let cv_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Variance.CV.month ?? 0) as NSNumber) ?? ""

                        averageTIRhca1c(hba1c_all, average_, median_, tir_low, tir_high, tir_, hba1c_, sd_, cv_)

                    case .total:
                        let hba1c_all = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.total ?? 0) as NSNumber) ?? ""
                        let average_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Average.total ?? 0) as NSNumber) ?? ""
                        let median_ = targetFormatter
                            .string(from: (state.statistics?.Statistics.Glucose.Median.total ?? 0) as NSNumber) ?? ""
                        let tir_low = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypos.total ?? 0) as NSNumber) ?? ""
                        let tir_high = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.Hypers.total ?? 0) as NSNumber) ??
                            ""
                        let tir_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Distribution.TIR.total ?? 0) as NSNumber) ?? ""
                        let hba1c_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.HbA1c.total ?? 0) as NSNumber) ?? ""
                        let sd_ = numberFormatter
                            .string(from: (state.statistics?.Statistics.Variance.SD.total ?? 0) as NSNumber) ?? ""
                        let cv_ = tirFormatter
                            .string(from: (state.statistics?.Statistics.Variance.CV.total ?? 0) as NSNumber) ?? ""

                        averageTIRhca1c(hba1c_all, average_, median_, tir_low, tir_high, tir_, hba1c_, sd_, cv_)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding([.bottom], 20)
            }
        }

        @ViewBuilder private func averageTIRhca1c(
            _ hba1c_all: String,
            _ average_: String,
            _ median_: String,
            _ tir_low: String,
            _ tir_high: String,
            _ tir_: String,
            _ hba1c_: String,
            _ sd_: String,
            _ cv_: String
        ) -> some View {
            HStack {
                Group {
                    if selectedState != .total {
                        HStack {
                            Text("HbA1c").font(.footnote).foregroundColor(.secondary)
                            Text(hba1c_).font(.footnote)
                        }
                    } else {
                        HStack {
                            Text(
                                "\(NSLocalizedString("HbA1c", comment: "")) (\(targetFormatter.string(from: (state.statistics?.GlucoseStorage_Days ?? 0) as NSNumber) ?? "") \(NSLocalizedString("days", comment: "")))"
                            )
                            .font(.footnote).foregroundColor(.secondary)
                            Text(hba1c_all).font(.footnote)
                        }
                    }
                    // Average as default. Changes to Median when clicking.
                    let textAverageTitle = NSLocalizedString("Average", comment: "")
                    let textMedianTitle = NSLocalizedString("Median", comment: "")
                    let cgmReadingsTitle = NSLocalizedString("Readings", comment: "CGM readings in statPanel")

                    HStack {
                        Text(averageOrMedianTitle).font(.footnote).foregroundColor(.secondary)
                        if averageOrMedianTitle == textAverageTitle {
                            Text(averageOrmedian == "" ? average_ : average_).font(.footnote)
                        } else if averageOrMedianTitle == textMedianTitle {
                            Text(averageOrmedian == "" ? median_ : median_).font(.footnote)
                        } else if averageOrMedianTitle == cgmReadingsTitle {
                            Text(
                                averageOrmedian != "0" ? tirFormatter
                                    .string(from: (state.statistics?.Statistics.LoopCycles.readings ?? 0) as NSNumber) ?? "" : ""
                            )
                            .font(.footnote)
                        }
                    }.onTapGesture {
                        if averageOrMedianTitle == textAverageTitle {
                            averageOrMedianTitle = textMedianTitle
                            averageOrmedian = median_
                        } else if averageOrMedianTitle == textMedianTitle {
                            averageOrMedianTitle = cgmReadingsTitle
                            averageOrmedian = tirFormatter
                                .string(from: (state.statistics?.Statistics.LoopCycles.readings ?? 0) as NSNumber) ?? ""
                        } else if averageOrMedianTitle == cgmReadingsTitle {
                            averageOrMedianTitle = textAverageTitle
                            averageOrmedian = average_
                        }
                    }
                    .frame(minWidth: 110)
                    // CV as default. Changes to SD when clicking
                    let text_CV_Title = NSLocalizedString("CV", comment: "")
                    let text_SD_Title = NSLocalizedString("SD", comment: "")

                    HStack {
                        Text(CV_or_SD_Title).font(.footnote).foregroundColor(.secondary)
                        if CV_or_SD_Title == text_CV_Title {
                            Text(CVorSD == "" ? cv_ : cv_).font(.footnote)
                        } else {
                            Text(CVorSD == "" ? sd_ : sd_).font(.footnote)
                        }
                    }.onTapGesture {
                        if CV_or_SD_Title == text_CV_Title {
                            CV_or_SD_Title = text_SD_Title
                            CVorSD = sd_
                        } else {
                            CV_or_SD_Title = text_CV_Title
                            CVorSD = cv_
                        }
                    }
                }
            }
            HStack {
                Group {
                    HStack {
                        Text(
                            NSLocalizedString("Low", comment: " ")
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)

                        Text(tir_low + " %").font(.footnote).foregroundColor(.loopRed)
                    }

                    HStack {
                        Text("Normal").font(.footnote).foregroundColor(.secondary)
                        Text(tir_ + " %").font(.footnote).foregroundColor(.loopGreen)
                    }

                    HStack {
                        Text(
                            NSLocalizedString("High", comment: " ")
                        )
                        .font(.footnote).foregroundColor(.secondary)

                        Text(tir_high + " %").font(.footnote).foregroundColor(.loopYellow)
                    }
                }
            }

            if state.settingsManager.preferences.displayLoops {
                HStack {
                    Group {
                        let loopTitle = NSLocalizedString("Loops", comment: "Nr of Loops in statPanel")
                        let errorTitle = NSLocalizedString("Errors", comment: "Loop Errors in statPanel")

                        HStack {
                            Text(loopStatTitle).font(.footnote).foregroundColor(.secondary)
                            Text(
                                loopStatTitle == loopTitle ? tirFormatter
                                    .string(from: (state.statistics?.Statistics.LoopCycles.loops ?? 0) as NSNumber) ?? "" :
                                    tirFormatter
                                    .string(from: (state.statistics?.Statistics.LoopCycles.errors ?? 0) as NSNumber) ?? ""
                            ).font(.footnote)
                        }.onTapGesture {
                            if loopStatTitle == loopTitle {
                                loopStatTitle = errorTitle
                            } else if loopStatTitle == errorTitle {
                                loopStatTitle = loopTitle
                            }
                        }

                        HStack {
                            Text("Interval").font(.footnote)
                                .foregroundColor(.secondary)
                            Text(
                                targetFormatter
                                    .string(from: (state.statistics?.Statistics.LoopCycles.avg_interval ?? 0) as NSNumber) ??
                                    ""
                            ).font(.footnote)
                        }

                        HStack {
                            Text("Duration").font(.footnote)
                                .foregroundColor(.secondary)
                            Text(
                                numberFormatter
                                    .string(
                                        from: (state.statistics?.Statistics.LoopCycles.median_duration ?? 0) as NSNumber
                                    ) ?? ""
                            ).font(.footnote)
                        }
                    }
                }
            }
        }

        var legendPanel: some View {
            ZStack {
                HStack(alignment: .center) {
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
                }
                .frame(maxWidth: .infinity)
                .padding([.bottom], 20)
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
                    suggestion: $state.suggestion,
                    statistcs: $state.statistics,
                    tempBasals: $state.tempBasals,
                    boluses: $state.boluses,
                    suspensions: $state.suspensions,
                    hours: .constant(state.filteredHours),
                    maxBasal: $state.maxBasal,
                    autotunedBasalProfile: $state.autotunedBasalProfile,
                    basalProfile: $state.basalProfile,
                    tempTargets: $state.tempTargets,
                    carbs: $state.carbs,
                    timerDate: $state.timerDate,
                    units: $state.units,
                    smooth: $state.smooth
                )
            }
            .padding(.bottom)
            .modal(for: .dataTable, from: self)
        }

        @ViewBuilder private func bottomPanel(_ geo: GeometryProxy) -> some View {
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 50 + geo.safeAreaInsets.bottom)

                HStack {
                    Button { state.showModal(for: .addCarbs) }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image("carbs")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 24, height: 24)
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
                    }
                    Spacer()
                    Button { state.showModal(for: .addTempTarget) }
                    label: {
                        Image("target")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }.foregroundColor(.loopGreen)
                    Spacer()
                    Button { state.showModal(for: .bolus(waitForSuggestion: false)) }
                    label: {
                        Image("bolus")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }.foregroundColor(.insulin)
                    Spacer()
                    if state.allowManualTemp {
                        Button { state.showModal(for: .manualTempBasal) }
                        label: {
                            Image("bolus1")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .padding(8)
                        }.foregroundColor(.insulin)
                        Spacer()
                    }
                    Button { state.showModal(for: .settings) }
                    label: {
                        Image("settings1")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(8)
                    }.foregroundColor(.loopGray)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, geo.safeAreaInsets.bottom)
            }
        }

        var body: some View {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    header(geo)
                    infoPanel
                    mainChart
                    legendPanel
                    statPanel()
                    bottomPanel(geo)
                }
                .edgesIgnoringSafeArea(.vertical)
            }
            .onAppear(perform: configureView)
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .popup(isPresented: isStatusPopupPresented, alignment: .top, direction: .top) {
                popup
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(UIColor.darkGray))
                    )
                    .onTapGesture {
                        isStatusPopupPresented = false
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onEnded { value in
                                if value.translation.height < 0 {
                                    isStatusPopupPresented = false
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
                }
            }
        }
    }
}
