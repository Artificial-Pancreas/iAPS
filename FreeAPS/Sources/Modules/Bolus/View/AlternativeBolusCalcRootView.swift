import SwiftUI
import Swinject

extension Bolus {
    // alternative bolus calc
    struct AlternativeBolusCalcRootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        @ObservedObject var state: StateModel

        @State private var showInfo = false
        @State var insulinCalculated: Decimal = 0

        @Environment(\.colorScheme) var colorScheme

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
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
                    HStack {
                        Text("Glucose")
                        DecimalTextField(
                            "0",
                            value: Binding(
                                get: {
                                    if state.units == .mmolL {
                                        return state.currentBG.asMmolL
                                    } else {
                                        return state.currentBG
                                    }
                                },
                                set: { newValue in
                                    if state.units == .mmolL {
                                        state.currentBG = newValue.asMmolL
                                    } else {
                                        state.currentBG = newValue
                                    }
                                }
                            ),
                            formatter: gluoseFormatter,
                            autofocus: false,
                            cleanInput: true
                        )
                        .onChange(of: state.currentBG) { newValue in
                            if newValue > 500 {
                                state.currentBG = 500 // ensure that user can not input more than 500 mg/dL
                            }
                            insulinCalculated = state.calculateInsulin()
                        }
                        Text(state.units.rawValue)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    HStack {
                        Button(action: {
                            showInfo.toggle()
                            insulinCalculated = state.calculateInsulin()
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
                                insulinCalculated = state.calculateInsulin()
                            }
                        }
                    }
                }
                header: { Text("Values") }

                Section {
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
                                    .string(from: Double(insulinCalculated) as NSNumber)!
                            )
                            let unit = NSLocalizedString(
                                " U",
                                comment: "Unit in number of units delivered (keep the space character!)"
                            )
                            Text(unit).foregroundColor(.secondary)
                        }.contentShape(Rectangle())
                            .onTapGesture {
                                state.amount = insulinCalculated
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
                                Text(!(state.amount > state.maxBolus) ? "U" : "😵").foregroundColor(.secondary)
                            }
                        }
                    }
                }
                header: { Text("Bolus") }

                Section {
                    Button(action: {
                        state.add()
                    }) {
                        Text(!(state.amount > state.maxBolus) ? "Enact bolus" : "Max Bolus exceeded!")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(
                        state.amount <= 0 || state.amount > state.maxBolus
                    )
                }
                .onAppear {
                    configureView {
                        state.waitForSuggestionInitial = waitForSuggestion
                        state.waitForSuggestion = waitForSuggestion
                    }
                }
                .navigationTitle("Enact Bolus")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Close", action: state.hideModal))
            }
            .blur(radius: showInfo ? 3 : 0)
            .popup(isPresented: showInfo) {
                bolusInfoAlternativeCalculator
            }
        }

        // calculation showed in popup
        var bolusInfoAlternativeCalculator: some View {
            let unit = NSLocalizedString(
                " U",
                comment: "Unit in number of units delivered (keep the space character!)"
            )

            return VStack {
                VStack {
                    VStack {
                        HStack {
                            Text("Calculations")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 10)
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
                            Text(target.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
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
                    .padding()

                    VStack {
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
                            Text(unit)
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
                            Text(unit)
                                .foregroundColor(.secondary)
                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let iobCalc = state.iobInsulinReduction
                            // rounding
                            let iobCalcAsDouble = NSDecimalNumber(decimal: iobCalc).doubleValue
                            let roundedIobCalc = Decimal(round(100 * iobCalcAsDouble) / 100)
                            Text(roundedIobCalc.formatted())
                            Text(unit).foregroundColor(.secondary)
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
                            Text(unit)
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
                            Text(unit)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()

                    Divider()
                        .fontWeight(.bold)

                    HStack {
                        Text("Full Bolus")
                            .foregroundColor(.secondary)
                        Spacer()
                        let insulin = state.roundedWholeCalc
                        Text(insulin.formatted()).foregroundStyle(state.roundedWholeCalc < 0 ? Color.loopRed : Color.primary)
                        Text(unit)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    Divider()
                        .fontWeight(.bold)

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
                        Text(unit)
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
                        Text(unit)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .padding(.top, 10)
                .padding(.bottom, 15)

                // Hide button
                VStack {
                    Button { showInfo = false }
                    label: {
                        Text("OK")
                    }
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
    }
}
