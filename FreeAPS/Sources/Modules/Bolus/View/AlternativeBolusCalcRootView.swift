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
        @State private var calculatorDetent = PresentationDetent.medium

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
                    if state.waitForSuggestion {
                        Text("Please wait")
                    } else {
                        predictionChart
                    }
                } header: { Text("Predictions") }

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

                } header: { Text("Bolus") }

                if state.amount > 0 {
                    Section {
                        Button {
                            keepForNextWiew = true
                            state.add()
                        }
                        label: { Text(exceededMaxBolus ? "Max Bolus exceeded!" : "Enact bolus") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .disabled(disabled)
                            .listRowBackground(!disabled ? Color(.systemBlue) : Color(.systemGray4))
                            .tint(.white)
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
                    carbsView()
                }
                label: {
                    HStack {
                        Image(systemName: "chevron.backward")
                        Text("Meal")
                    }
                },
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
                    state.delete(deleteTwice: true, meal: meal)
                } else if fetch, !keepForNextWiew, state.useCalc {
                    state.delete(deleteTwice: false, meal: meal)
                }
            }
            .sheet(isPresented: $showInfo) {
                bolusInfoAlternativeCalculator
                    .presentationDetents(
                        [fetch ? .fraction(0.75) : .fraction(0.60), .large],
                        selection: $calculatorDetent
                    )
            }
        }

        var predictionChart: some View {
            ZStack {
                PredictionView(
                    predictions: $state.predictions, units: $state.units, eventualBG: $state.evBG, target: $state.target,
                    displayPredictions: $state.displayPredictions
                )
            }
        }

        // Pop-up
        var bolusInfoAlternativeCalculator: some View {
            NavigationStack {
                VStack {
                    VStack {
                        VStack(spacing: Config.spacing) {
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
                                Text(insulin.formatted())
                                    .foregroundStyle(state.roundedWholeCalc < 0 ? Color.loopRed : Color.primary)
                                Text(" U")
                                    .foregroundColor(.secondary)
                            }
                        }.padding(.horizontal)
                        Divider().frame(height: Config.dividerHeight)
                        results.padding()
                        if exceededMaxBolus {
                            Divider().frame(height: Config.dividerHeight) // .overlay(Config.overlayColour)
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

                    Spacer()
                }
                .navigationTitle("Calculations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close", action: { showInfo = false })
                    }
                }
            }
        }

        private var disabled: Bool {
            state.amount <= 0 || state.amount > state.maxBolus
        }

        var changed: Bool {
            ((meal.first?.carbs ?? 0) > 0) || ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        var hasFatOrProtein: Bool {
            ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        func carbsView() {
            if fetch {
                keepForNextWiew = true
                state.backToCarbsView(complexEntry: true, meal, override: false)
            } else {
                state.backToCarbsView(complexEntry: false, meal, override: true)
            }
        }

        var mealEntries: some View {
            VStack {
                if let carbs = meal.first?.carbs, carbs > 0 {
                    HStack {
                        Text("Carbs").foregroundColor(.secondary)
                        Spacer()
                        Text(carbs.formatted())
                        Text("g").foregroundColor(.secondary)
                    }
                }
                if let fat = meal.first?.fat, fat > 0 {
                    HStack {
                        Text("Fat").foregroundColor(.secondary)
                        Spacer()
                        Text(fat.formatted())
                        Text("g").foregroundColor(.secondary)
                    }
                }
                if let protein = meal.first?.protein, protein > 0 {
                    HStack {
                        Text("Protein").foregroundColor(.secondary)
                        Spacer()
                        Text(protein.formatted())
                        Text("g").foregroundColor(.secondary)
                    }
                }
                if let note = meal.first?.note, note != "" {
                    HStack {
                        Text("Note").foregroundColor(.secondary)
                        Spacer()
                        Text(note).foregroundColor(.secondary)
                    }
                }
            }
        }

        var settings: some View {
            VStack {
                HStack {
                    Text("Carb Ratio")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    Text(state.carbRatio.formatted())
                        .frame(minWidth: 40, alignment: .trailing)
                    Text(NSLocalizedString("g/U", comment: " grams per Unit"))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)
                    Spacer()
                }
                HStack {
                    Text("ISF")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let isf = state.isf
                    Text(isf.formatted())
                        .frame(minWidth: 40, alignment: .trailing)
                    Text(state.units.rawValue + NSLocalizedString("/U", comment: "/Insulin unit"))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)
                    Spacer()
                }
                HStack {
                    Text("Target Glucose")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let target = state.units == .mmolL ? state.target.asMmolL : state.target

                    Text(
                        target
                            .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                    ).frame(minWidth: 40, alignment: .trailing)
                    Text(state.units.rawValue)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)
                    Spacer()
                }
                HStack {
                    Text("Basal")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let basal = state.basal
                    Text(basal.formatted())
                        .frame(minWidth: 40, alignment: .trailing)
                    Text(NSLocalizedString("U/h", comment: " Units per hour"))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)
                    Spacer()
                }
                HStack {
                    Text("Fraction")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let fraction = state.fraction
                    Text(fraction.formatted())
                        .frame(minWidth: 40, alignment: .trailing)
                    Text("").frame(minWidth: 70, alignment: .leading)
                    Spacer()
                }
                if state.useFattyMealCorrectionFactor {
                    HStack {
                        Text("Fatty Meal Factor")
                            .foregroundColor(.orange)
                            .frame(minWidth: 115, alignment: .leading)
                        let fraction = state.fattyMealFactor
                        Text(fraction.formatted())
                        foregroundColor(.orange)
                            .frame(minWidth: 40, alignment: .trailing)
                        Text("").frame(minWidth: 70, alignment: .leading)
                        Spacer()
                    }
                }
            }
        }

        var insulinParts: some View {
            VStack(spacing: Config.spacing) {
                HStack(alignment: .center, spacing: nil) {
                    Text("Glucose")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let glucose = state.units == .mmolL ? state.currentBG.asMmolL : state.currentBG
                    Text(glucose.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                        .frame(minWidth: 40, alignment: .trailing)
                    Text(state.units.rawValue)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .frame(minWidth: 20, alignment: .trailing)
                    Spacer()

                    let targetDifferenceInsulin = state.targetDifferenceInsulin
                    // rounding
                    let targetDifferenceInsulinAsDouble = NSDecimalNumber(decimal: targetDifferenceInsulin).doubleValue
                    let roundedTargetDifferenceInsulin = Decimal(round(100 * targetDifferenceInsulinAsDouble) / 100)
                    Text(roundedTargetDifferenceInsulin.formatted())
                    Text(" U")
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .center, spacing: nil) {
                    Text("IOB")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let iob = state.iob
                    // rounding
                    let iobAsDouble = NSDecimalNumber(decimal: iob).doubleValue
                    let roundedIob = Decimal(round(100 * iobAsDouble) / 100)
                    Text(roundedIob.formatted())
                        .frame(minWidth: 40, alignment: .trailing)
                    Text("U")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .frame(minWidth: 20, alignment: .trailing)
                    Spacer()

                    let iobCalc = state.iobInsulinReduction
                    // rounding
                    let iobCalcAsDouble = NSDecimalNumber(decimal: iobCalc).doubleValue
                    let roundedIobCalc = Decimal(round(100 * iobCalcAsDouble) / 100)
                    Text(roundedIobCalc.formatted())
                    Text(" U").foregroundColor(.secondary)
                }
                HStack(alignment: .center, spacing: nil) {
                    Text("Trend")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let trend = state.units == .mmolL ? state.deltaBG.asMmolL : state.deltaBG
                    Text(trend.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                        .frame(minWidth: 40, alignment: .trailing)
                    Text(state.units.rawValue).foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .frame(minWidth: 20, alignment: .trailing)
                    Spacer()

                    let trendInsulin = state.fifteenMinInsulin
                    // rounding
                    let trendInsulinAsDouble = NSDecimalNumber(decimal: trendInsulin).doubleValue
                    let roundedTrendInsulin = Decimal(round(100 * trendInsulinAsDouble) / 100)
                    Text(roundedTrendInsulin.formatted())
                    Text(" U")
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .center, spacing: nil) {
                    Text("COB")
                        .foregroundColor(.secondary)
                        .frame(minWidth: 115, alignment: .leading)
                    let cob = state.cob
                    Text(cob.formatted())
                        .frame(minWidth: 40, alignment: .trailing)

                    let unitGrams = NSLocalizedString("g", comment: "grams")
                    Text(unitGrams).foregroundColor(.secondary)
                        .frame(minWidth: 70, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .frame(minWidth: 20, alignment: .trailing)
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
