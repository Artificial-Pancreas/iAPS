import Charts
import CoreData
import SwiftUI
import Swinject

extension Bolus {
    struct AlternativeBolusCalcRootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let fetch: Bool
        @StateObject var state: StateModel
        @State private var showInfo = false
        @State private var exceededMaxBolus = false
        @State private var keepForNextWiew: Bool = false

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let overlayColour: Color = .white // Currently commented out
            static let spacing: CGFloat = 3
        }

        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Meals.entity(),
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        ) var meal: FetchedResults<Meals>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var mealFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var gluoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var fractionDigits: Int {
            if state.units == .mmolL {
                return 1
            } else { return 0 }
        }

        var body: some View {
            Form {
                Section {
                    chart()
                } header: {
                    Text("Predictions")
                }

                Section {}
                if fetch {
                    Section {
                        mealEntries
                    } header: { Text("Meal Summary") }
                }

                Section {
                    HStack {
                        Button(action: {
                            showInfo.toggle()
                        }, label: {
                            Image(systemName: "info.circle")
                            Text("Calculations")
                        })
                            .foregroundStyle(.blue)
                            .font(.footnote)
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if state.fattyMeals {
                            Spacer()
                            Toggle(isOn: $state.useFattyMealCorrectionFactor) {
                                Text("Fatty Meal")
                            }
                            .toggleStyle(CheckboxToggleStyle())
                            .font(.footnote)
                            .onChange(of: state.useFattyMealCorrectionFactor) { _ in
                                state.insulinCalculated = state.calculateInsulin()
                            }
                        }
                    }

                    if state.waitForSuggestion {
                        HStack {
                            Text("Wait please").foregroundColor(.secondary)
                            Spacer()
                            ActivityIndicator(isAnimating: .constant(true), style: .medium) // fix iOS 15 bug
                        }
                    } else {
                        HStack {
                            Text("Recommended Bolus")
                            Spacer()
                            Text(
                                formatter
                                    .string(from: Double(state.insulinCalculated) as NSNumber) ?? ""
                            )
                            Text(
                                NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                            ).foregroundColor(.secondary)
                        }.contentShape(Rectangle())
                            .onTapGesture { state.amount = state.insulinCalculated }
                    }

                    if !state.waitForSuggestion {
                        HStack {
                            Text("Bolus")
                            Spacer()
                            DecimalTextField(
                                "0",
                                value: $state.amount,
                                formatter: formatter,
                                autofocus: false,
                                cleanInput: true
                            )
                            Text(exceededMaxBolus ? "😵" : " U").foregroundColor(.secondary)
                        }
                        .onChange(of: state.amount) { newValue in
                            if newValue > state.maxBolus {
                                exceededMaxBolus = true
                            } else {
                                exceededMaxBolus = false
                            }
                        }
                    }
                } header: { Text("Bolus") }

                if state.amount > 0 {
                    Section {
                        Button {
                            keepForNextWiew = true
                            state.add()
                        }
                        label: { Text(exceededMaxBolus ? "Max Bolus exceeded!" : "Enact bolus") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(exceededMaxBolus ? .loopRed : .accentColor)
                            .disabled(
                                state.amount <= 0 || state.amount > state.maxBolus
                            )
                    }
                }
                if state.amount <= 0 {
                    Section {
                        Button {
                            keepForNextWiew = true
                            state.showModal(for: nil)
                        }
                        label: { Text("Continue without bolus") }.frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .blur(radius: showInfo ? 3 : 0)
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button {
                    carbssView()
                }
                label: { Text(fetch ? "Back" : "Meal") },

                trailing: Button { state.hideModal() }
                label: { Text("Close") }
            )
            .onAppear {
                configureView {
                    state.waitForSuggestionInitial = waitForSuggestion
                    state.waitForSuggestion = waitForSuggestion
                    state.insulinCalculated = state.calculateInsulin()
                }
            }
            .onDisappear {
                if fetch, hasFatOrProtein, !keepForNextWiew, state.useCalc {
                    state.delete(deleteTwice: true, id: meal.first?.id ?? "")
                } else if fetch, !keepForNextWiew, state.useCalc {
                    state.delete(deleteTwice: false, id: meal.first?.id ?? "")
                }
            }
            .popup(isPresented: showInfo) {
                bolusInfoAlternativeCalculator
            }
        }

        func chart() -> some View {
            // Data Source
            let iob = state.provider.suggestion?.predictions?.iob ?? [Int]()
            let cob = state.provider.suggestion?.predictions?.cob ?? [Int]()
            let uam = state.provider.suggestion?.predictions?.uam ?? [Int]()
            let zt = state.provider.suggestion?.predictions?.zt ?? [Int]()
            let count = max(iob.count, cob.count, uam.count, zt.count)
            var now = Date.now
            var startIndex = 0
            let conversion = state.units == .mmolL ? 0.0555 : 1
            // Organize the data needed for prediction chart.
            var data = [ChartData]()
            repeat {
                now = now.addingTimeInterval(5.minutes.timeInterval)
                if startIndex < count {
                    let addedData = ChartData(
                        date: now,
                        iob: startIndex < iob.count ? Double(iob[startIndex]) * conversion : 0,
                        zt: startIndex < zt.count ? Double(zt[startIndex]) * conversion : 0,
                        cob: startIndex < cob.count ? Double(cob[startIndex]) * conversion : 0,
                        uam: startIndex < uam.count ? Double(uam[startIndex]) * conversion : 0,
                        id: UUID()
                    )
                    data.append(addedData)
                }
                startIndex += 1
            } while startIndex < count
            // Chart
            return Chart(data) { item in
                // Remove 0 (empty) values
                if item.iob != 0 {
                    LineMark(
                        x: .value("Time", item.date),
                        y: .value("IOB", item.iob),
                        series: .value("IOB", "A")
                    )
                    .foregroundStyle(Color(.insulin))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if item.uam != 0 {
                    LineMark(
                        x: .value("Time", item.date),
                        y: .value("UAM", item.uam),
                        series: .value("UAM", "B")
                    )
                    .foregroundStyle(Color(.UAM))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if item.cob != 0 {
                    LineMark(
                        x: .value("Time", item.date),
                        y: .value("COB", item.cob),
                        series: .value("COB", "C")
                    )
                    .foregroundStyle(Color(.loopYellow))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if item.zt != 0 {
                    LineMark(
                        x: .value("Time", item.date),
                        y: .value("ZT", item.zt),
                        series: .value("ZT", "D")
                    )
                    .foregroundStyle(Color(.ZT))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .frame(minHeight: 150)
            .chartForegroundStyleScale([
                "IOB": Color(.insulin),
                "UAM": Color(.UAM),
                "COB": Color(.loopYellow),
                "ZT": Color(.ZT)
            ])
            .chartYAxisLabel("Glucose (" + state.units.rawValue + ")")
        }

        // Pop-up
        var bolusInfoAlternativeCalculator: some View {
            VStack {
                VStack {
                    VStack(spacing: Config.spacing) {
                        HStack {
                            Text("Calculations")
                                .font(.title3).frame(maxWidth: .infinity, alignment: .center)
                        }.padding(10)
                        if fetch {
                            mealEntries.padding()
                            Divider().frame(height: Config.dividerHeight) // .overlay(Config.overlayColour)
                        }
                        settings.padding()
                    }
                    Divider().frame(height: Config.dividerHeight) // .overlay(Config.overlayColour)
                    insulinParts.padding()
                    Divider().frame(height: Config.dividerHeight) // .overlay(Config.overlayColour)
                    VStack {
                        HStack {
                            Text("Full Bolus")
                                .foregroundColor(.secondary)
                            Spacer()
                            let insulin = state.roundedWholeCalc
                            Text(insulin.formatted()).foregroundStyle(state.roundedWholeCalc < 0 ? Color.loopRed : Color.primary)
                            Text(" U")
                                .foregroundColor(.secondary)
                        }
                    }.padding(.horizontal)
                    Divider().frame(height: Config.dividerHeight)
                    results.padding()
                    Divider().frame(height: Config.dividerHeight) // .overlay(Config.overlayColour)
                    if exceededMaxBolus {
                        HStack {
                            let maxBolus = state.maxBolus
                            let maxBolusFormatted = maxBolus.formatted()
                            Text("Your entered amount was limited by your max Bolus setting of \(maxBolusFormatted)\(" U")")
                        }
                        .padding()
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.loopRed)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 15)
                // Hide pop-up
                VStack {
                    Button { showInfo = false }
                    label: { Text("OK") }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .font(.system(size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 20)
            }
            .font(.footnote)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray4).opacity(0.9))
            )
        }

        var changed: Bool {
            ((meal.first?.carbs ?? 0) > 0) || ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        var hasFatOrProtein: Bool {
            ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        func carbssView() {
            let id_ = meal.first?.id ?? ""
            if fetch {
                keepForNextWiew = true
                state.backToCarbsView(complexEntry: fetch, id_)
            } else {
                state.showModal(for: .addCarbs(editMode: false))
            }
        }

        var mealEntries: some View {
            VStack {
                if let carbs = meal.first?.carbs, carbs > 0 {
                    HStack {
                        Text("Carbs")
                        Spacer()
                        Text(carbs.formatted())
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let fat = meal.first?.fat, fat > 0 {
                    HStack {
                        Text("Fat")
                        Spacer()
                        Text(fat.formatted())
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let protein = meal.first?.protein, protein > 0 {
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text(protein.formatted())
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let note = meal.first?.note, note != "" {
                    HStack {
                        Text("Note")
                        Spacer()
                        Text(note)
                    }.foregroundColor(.secondary)
                }
            }
        }

        var settings: some View {
            VStack {
                HStack {
                    Text("Carb Ratio")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(state.carbRatio.formatted())
                    Text(NSLocalizedString(" g/U", comment: " grams per Unit"))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("ISF")
                        .foregroundColor(.secondary)
                    Spacer()
                    let isf = state.isf
                    Text(isf.formatted())
                    Text(state.units.rawValue + NSLocalizedString("/U", comment: "/Insulin unit"))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Target Glucose")
                        .foregroundColor(.secondary)
                    Spacer()
                    let target = state.units == .mmolL ? state.target.asMmolL : state.target
                    Text(
                        target
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    )
                    Text(state.units.rawValue)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Basal")
                        .foregroundColor(.secondary)
                    Spacer()
                    let basal = state.basal
                    Text(basal.formatted())
                    Text(NSLocalizedString(" U/h", comment: " Units per hour"))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Fraction")
                        .foregroundColor(.secondary)
                    Spacer()
                    let fraction = state.fraction
                    Text(fraction.formatted())
                }
                if state.useFattyMealCorrectionFactor {
                    HStack {
                        Text("Fatty Meal Factor")
                            .foregroundColor(.orange)
                        Spacer()
                        let fraction = state.fattyMealFactor
                        Text(fraction.formatted())
                            .foregroundColor(.orange)
                    }
                }
            }
        }

        var insulinParts: some View {
            VStack(spacing: Config.spacing) {
                HStack {
                    Text("Glucose")
                        .foregroundColor(.secondary)
                    Spacer()
                    let glucose = state.units == .mmolL ? state.currentBG.asMmolL : state.currentBG
                    Text(glucose.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                    Text(state.units.rawValue)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "arrow.right")
                    Spacer()

                    let targetDifferenceInsulin = state.targetDifferenceInsulin
                    // rounding
                    let targetDifferenceInsulinAsDouble = NSDecimalNumber(decimal: targetDifferenceInsulin).doubleValue
                    let roundedTargetDifferenceInsulin = Decimal(round(100 * targetDifferenceInsulinAsDouble) / 100)
                    Text(roundedTargetDifferenceInsulin.formatted())
                    Text(" U")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("IOB")
                        .foregroundColor(.secondary)
                    Spacer()
                    let iob = state.iob
                    // rounding
                    let iobAsDouble = NSDecimalNumber(decimal: iob).doubleValue
                    let roundedIob = Decimal(round(100 * iobAsDouble) / 100)
                    Text(roundedIob.formatted())
                    Text(" U")
                        .foregroundColor(.secondary)
                    Spacer()

                    Image(systemName: "arrow.right")
                    Spacer()

                    let iobCalc = state.iobInsulinReduction
                    // rounding
                    let iobCalcAsDouble = NSDecimalNumber(decimal: iobCalc).doubleValue
                    let roundedIobCalc = Decimal(round(100 * iobCalcAsDouble) / 100)
                    Text(roundedIobCalc.formatted())
                    Text(" U").foregroundColor(.secondary)
                }
                HStack {
                    Text("Trend")
                        .foregroundColor(.secondary)
                    Spacer()
                    let trend = state.units == .mmolL ? state.deltaBG.asMmolL : state.deltaBG
                    Text(trend.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                    Text(state.units.rawValue).foregroundColor(.secondary)
                    Spacer()

                    Image(systemName: "arrow.right")
                    Spacer()

                    let trendInsulin = state.fifteenMinInsulin
                    // rounding
                    let trendInsulinAsDouble = NSDecimalNumber(decimal: trendInsulin).doubleValue
                    let roundedTrendInsulin = Decimal(round(100 * trendInsulinAsDouble) / 100)
                    Text(roundedTrendInsulin.formatted())
                    Text(" U")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("COB")
                        .foregroundColor(.secondary)
                    Spacer()
                    let cob = state.cob
                    Text(cob.formatted())

                    let unitGrams = NSLocalizedString(" g", comment: "grams")
                    Text(unitGrams).foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: "arrow.right")
                    Spacer()

                    let insulinCob = state.wholeCobInsulin
                    // rounding
                    let insulinCobAsDouble = NSDecimalNumber(decimal: insulinCob).doubleValue
                    let roundedInsulinCob = Decimal(round(100 * insulinCobAsDouble) / 100)
                    Text(roundedInsulinCob.formatted())
                    Text(" U")
                        .foregroundColor(.secondary)
                }
            }
        }

        var results: some View {
            VStack {
                HStack {
                    Text("Result")
                        .fontWeight(.bold)
                    Spacer()
                    let fraction = state.fraction
                    Text(fraction.formatted())
                    Text(" x ")
                        .foregroundColor(.secondary)

                    // if fatty meal is chosen
                    if state.useFattyMealCorrectionFactor {
                        let fattyMealFactor = state.fattyMealFactor
                        Text(fattyMealFactor.formatted())
                            .foregroundColor(.orange)
                        Text(" x ")
                            .foregroundColor(.secondary)
                    }

                    let insulin = state.roundedWholeCalc
                    Text(insulin.formatted()).foregroundStyle(state.roundedWholeCalc < 0 ? Color.loopRed : Color.primary)
                    Text(" U")
                        .foregroundColor(.secondary)
                    Text(" = ")
                        .foregroundColor(.secondary)

                    let result = state.insulinCalculated
                    // rounding
                    let resultAsDouble = NSDecimalNumber(decimal: result).doubleValue
                    let roundedResult = Decimal(round(100 * resultAsDouble) / 100)
                    Text(roundedResult.formatted())
                        .fontWeight(.bold)
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    Text(" U")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
