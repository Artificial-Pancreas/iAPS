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
        @State private var remoteBolusAlert: Alert?
        @State private var isRemoteBolusAlertPresented: Bool = false

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let overlayColour: Color = .white // Currently commented out
            static let spacing: CGFloat = 3
        }

        @Environment(\.colorScheme) var colorScheme
        @FocusState private var isFocused: Bool

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
                } header: { Text("Status") }

                Section {}
                if fetch {
                    Section {
                        mealEntries
                    } // header: { Text("Meal Summary") }
                }

                Section {
                    HStack {
                        Button(action: {
                            showInfo.toggle()
                        }, label: {
                            Image(systemName: "info.bubble")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(colorScheme == .light ? .black : .white, .blue)
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
                            Text("Insulin recommended")
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
                            cleanInput: true,
                            useButtons: false
                        )
                        Text(exceededMaxBolus ? "😵" : " U").foregroundColor(.secondary)
                    }
                    .focused($isFocused)
                    .onChange(of: state.amount) { newValue in
                        if newValue > state.maxBolus {
                            exceededMaxBolus = true
                        } else {
                            exceededMaxBolus = false
                        }
                    }

                } header: {
                    HStack {
                        Text("Bolus")
                        if isFocused {
                            Button { isFocused = false } label: {
                                HStack {
                                    Text("Hide").foregroundStyle(.gray)
                                    Image(systemName: "keyboard")
                                        .symbolRenderingMode(.monochrome).foregroundStyle(colorScheme == .dark ? .white : .black)
                                }.frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .controlSize(.mini)
                        }
                    }
                }

                if state.amount > 0 {
                    Section {
                        Button {
                            if let remoteBolus = state.remoteBolus() {
                                remoteBolusAlert = Alert(
                                    title: Text("A Remote Bolus Was Just Delivered!"),
                                    message: Text(remoteBolus),
                                    primaryButton: .destructive(Text("Bolus"), action: {
                                        keepForNextWiew = true
                                        state.add()
                                    }),
                                    secondaryButton: .cancel()
                                )
                                isRemoteBolusAlertPresented = true
                            } else {
                                keepForNextWiew = true
                                state.add()
                            }
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
                        label: {
                            fetch ?
                                Text("Save Meal without bolus") :
                                Text("Continue without bolus") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color(.systemBlue))
                            .tint(.white)
                    }
                }
            }
            .compactSectionSpacing()
            .alert(isPresented: $isRemoteBolusAlertPresented) {
                remoteBolusAlert!
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .blur(radius: showInfo ? 20 : 0)
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
                label: { Text("Cancel") }
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
            .popup(isPresented: showInfo) {
                bolusInfoAlternativeCalculator
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
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray4).opacity(0.9))
            )
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
                state.backToCarbsView(complexEntry: hasFatOrProtein, meal, override: false, deleteNothing: false, editMode: true)
            } else {
                state.backToCarbsView(complexEntry: false, meal, override: true, deleteNothing: true, editMode: false)
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
