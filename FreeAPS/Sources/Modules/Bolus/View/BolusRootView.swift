import SwiftUI
import Swinject

extension Bolus {
    struct RootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        @StateObject var state = StateModel()

        var body: some View {
            if state.useCalc {
                // Show alternative bolus calc
                BolusCalcView1(resolver: resolver, waitForSuggestion: waitForSuggestion, state: state)
            } else {
                // show iAPS standard bolus calc
                BolusCalcView2(resolver: resolver, waitForSuggestion: waitForSuggestion, state: state)
            }
        }
    }

    // alternative bolus calc
    struct BolusCalcView1: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        @ObservedObject var state: StateModel

        @State private var isAddInsulinAlertPresented = false
        @State private var showInfo = false
        @State private var carbsWarning = false
        @State var insulinCalculated: Decimal = 0

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
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
                        Text("Blood glucose")
                        DecimalTextField(
                            "0",
                            value: $state.BZ,
                            formatter: formatter,
                            autofocus: false,
                            cleanInput: true
                        )
                        .onChange(of: state.BZ) { newValue in
                            if newValue > 500 {
                                state.BZ = 500 // ensure that user can not input more than 500 mg/dL
                            }
                            insulinCalculated = state.calculateInsulin()
                        }
                        Text(
                            NSLocalizedString("mg/dL", comment: "mg/dL")
                        ).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())

                    HStack {
                        Text("Carbs")
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.Carbs,
                            formatter: formatter,
                            autofocus: false,
                            cleanInput: true
                        )
                        .onChange(of: state.Carbs) { newValue in
                            if newValue > 250 {
                                state.Carbs = 250 // ensure that user can not input more than 200g of carbs accidentally
                            }
                            insulinCalculated = state.calculateInsulin()
                            carbsWarning.toggle()
                        }
                        Text(
                            NSLocalizedString("g", comment: "grams")
                        )
                        .foregroundColor(.secondary)
                        .alert("Warning! Too much carbs entered!", isPresented: $carbsWarning) {
                            Button("OK", role: .cancel) {}
                        }
                    }

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
                }
                header: { Text("Values") }

                Section {
                    HStack {
                        Text("Recommended Bolus")
                        Spacer()

                        Text(
                            formatter
                                .string(from: Double(insulinCalculated) as NSNumber)!
                        )
                        Text("IE").foregroundColor(.secondary)
                    }.contentShape(Rectangle())
                        .onTapGesture {
                            state.amount = insulinCalculated
                            if insulinCalculated <= 0 {
                                insulinCalculated = 0
                            }
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
                            Text("IE").foregroundColor(.secondary)
                        }
                        HStack {
                            Spacer()
                            Button(action: {
                                if waitForSuggestion {
                                    state.showModal(for: nil)
                                } else {
                                    isAddInsulinAlertPresented = true
                                }
                            }, label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 28))
                            })
                                .disabled(state.amount <= 0 || state.amount > state.maxBolus * 3)
                                .buttonStyle(PlainButtonStyle())
                                .padding(.trailing, 10)
                        }
                    }
                }
                header: { Text("Bolus") }

                Section {
                    Button(action: {
                        state.add()
                    }) {
                        Text("Enact bolus")
                            .font(.title3)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(
                        state.amount <= 0 || state.amount > state.maxBolus
                    )
                }

                .alert(isPresented: $isAddInsulinAlertPresented) {
                    let amount = formatter
                        .string(from: state.amount as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit")
                    return Alert(
                        title: Text("Are you sure?"),
                        message: Text("Add \(amount) without bolusing"),
                        primaryButton: .destructive(
                            Text("Add"),
                            action: { state.addWithoutBolus() }
                        ),
                        secondaryButton: .cancel()
                    )
                }
                .onAppear {
                    configureView {
                        state.waitForSuggestionInitial = waitForSuggestion
                        state.waitForSuggestion = waitForSuggestion
                        // insulinCalculated = state.calculateInsulin()
                    }
                }
                .navigationTitle("Enact Bolus")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: state.hideModal))
            }
            .blur(radius: showInfo ? 3 : 0)
            .popup(isPresented: showInfo) {
                bolusInfoAlternativeCalculator
            }
        }

        // calculation showed in popup
        var bolusInfoAlternativeCalculator: some View {
            VStack {
                VStack {
                    VStack {
                        HStack {
                            Text("Calculations")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        HStack {
                            Text("Glucose")
                                .fontWeight(.semibold)
                            Spacer()
                            let glucose = state.currentBG
                            Text(glucose.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                            Text(state.units.rawValue)
                        }
                        HStack {
                            Text("ISF")
                                .fontWeight(.semibold)
                            Spacer()
                            let isf = state.isf
                            Text(isf.formatted())
                            Text(state.units.rawValue + NSLocalizedString("/U", comment: "/Insulin unit"))
                        }
                        HStack {
                            Text("Target Glucose")
                                .fontWeight(.semibold)
                            Spacer()
                            let target = state.units == .mmolL ? state.target.asMmolL : state.target
                            Text(target.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                            Text(state.units.rawValue)
                        }
                        HStack {
                            Text("Basal")
                                .fontWeight(.semibold)
                            Spacer()
                            let basal = state.basal
                            Text(basal.formatted())
                            Text(NSLocalizedString(" U/h", comment: " Units per hour"))
                        }
                        HStack {
                            Text("Fraction")
                                .fontWeight(.semibold)
                            Spacer()
                            let fraction = state.fraction
                            Text(fraction.formatted())
                        }
                    }
                    .padding()

                    VStack {
                        HStack {
                            Text("IOB")
                                .fontWeight(.semibold)
                            Spacer()
                            let iob = state.iob
                            // rounding
                            let iobAsDouble = NSDecimalNumber(decimal: iob).doubleValue
                            let roundedIob = Decimal(round(100 * iobAsDouble) / 100)
                            Text(roundedIob.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let iobCalc = state.showIobCalc
                            // rounding
                            let iobCalcAsDouble = NSDecimalNumber(decimal: iobCalc).doubleValue
                            let roundedIobCalc = Decimal(round(100 * iobCalcAsDouble) / 100)
                            Text(roundedIobCalc.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
                        }
                        HStack {
                            Text("Trend")
                                .fontWeight(.semibold)
                            Spacer()
                            let trend = state.DeltaBZ
                            Text(trend.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                            Text(state.units.rawValue)
                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let trendInsulin = state.InsulinfifteenMinDelta
                            // rounding
                            let trendInsulinAsDouble = NSDecimalNumber(decimal: trendInsulin).doubleValue
                            let roundedTrendInsulin = Decimal(round(100 * trendInsulinAsDouble) / 100)
                            Text(roundedTrendInsulin.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
                        }
                        HStack {
                            Text("COB")
                                .fontWeight(.semibold)
                            Spacer()
                            let cob = state.cob
                            Text(cob.formatted() + NSLocalizedString(" g", comment: "grams"))
                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let insulinCob = state.insulinWholeCOB
                            // rounding
                            let insulinCobAsDouble = NSDecimalNumber(decimal: insulinCob).doubleValue
                            let roundedInsulinCob = Decimal(round(100 * insulinCobAsDouble) / 100)
                            Text(roundedInsulinCob.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
                        }
                    }
                    .padding()

                    Divider()
                        .fontWeight(.bold)

                    HStack {
                        Text("Result")
                        Spacer()
                        let fraction = state.fraction
                        let insulin = state.roundedWholeCalc
                        let result = state.insulinCalculated
                        Text(
                            fraction.formatted() + " x " + insulin.formatted() + NSLocalizedString(" U", comment: "Insulin unit")
                        )
                        Text(
                            " = " + result.formatted() + NSLocalizedString(" U", comment: "Insulin unit")
                        )
                    }
                    .fontWeight(.bold)
                    .padding()
                }
                .padding(.top, 20)
                Spacer()

                // Hide button
                VStack {
                    Button { showInfo = false }
                    label: {
                        Text("OK")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
                .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemGray).opacity(0.9))
            )
        }
    }

    // default bolus calc code
    struct BolusCalcView2: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        @ObservedObject var state: StateModel

        @State private var isAddInsulinAlertPresented = false
        @State private var presentInfo = false
        @State private var displayError = false

        @Environment(\.colorScheme) var colorScheme

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
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
                                    .string(from: state.insulinRecommended as NSNumber)! +
                                    NSLocalizedString(" U", comment: "Insulin unit")
                            ).foregroundColor((state.error && state.insulinRecommended > 0) ? .red : .secondary)
                        }.contentShape(Rectangle())
                            .onTapGesture {
                                if state.error, state.insulinRecommended > 0 { displayError = true }
                                else { state.amount = state.insulinRecommended }
                            }
                        HStack {
                            Image(systemName: "info.bubble").symbolRenderingMode(.palette).foregroundStyle(
                                .primary, .blue
                            )
                        }.onTapGesture {
                            presentInfo.toggle()
                        }
                    }
                }
                header: { Text("Recommendation") }

                if !state.waitForSuggestion {
                    Section {
                        HStack {
                            Text("Amount")
                            Spacer()
                            DecimalTextField(
                                "0",
                                value: $state.amount,
                                formatter: formatter,
                                autofocus: true,
                                cleanInput: true
                            )
                            Text("U").foregroundColor(.secondary)
                        }
                    }
                    header: { Text("Bolus") }
                    Section {
                        Button { state.add() }
                        label: { Text("Enact bolus") }
                            .disabled(state.amount <= 0)
                    }
                    Section {
                        if waitForSuggestion {
                            Button { state.showModal(for: nil) }
                            label: { Text("Continue without bolus") }
                        } else {
                            Button { isAddInsulinAlertPresented = true }
                            label: { Text("Add insulin without actually bolusing") }
                                .disabled(state.amount <= 0)
                        }
                    }
                    .alert(isPresented: $isAddInsulinAlertPresented) {
                        Alert(
                            title: Text("Are you sure?"),
                            message: Text(
                                NSLocalizedString("Add", comment: "Add insulin without bolusing alert") + " " + formatter
                                    .string(from: state.amount as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit") +
                                    NSLocalizedString(" without bolusing", comment: "Add insulin without bolusing alert")
                            ),
                            primaryButton: .destructive(
                                Text("Add"),
                                action: {
                                    state.addWithoutBolus()
                                    isAddInsulinAlertPresented = false
                                }
                            ),
                            secondaryButton: .cancel()
                        )
                    }
                }
            }
            .alert(isPresented: $displayError) {
                Alert(
                    title: Text("Warning!"),
                    message: Text("\n" + alertString() + "\n"),
                    primaryButton: .destructive(
                        Text("Add"),
                        action: {
                            state.amount = state.insulinRecommended
                            displayError = false
                        }
                    ),
                    secondaryButton: .cancel()
                )
            }.onAppear {
                configureView {
                    state.waitForSuggestionInitial = waitForSuggestion
                    state.waitForSuggestion = waitForSuggestion
                }
            }
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
            .popup(isPresented: presentInfo, alignment: .center, direction: .bottom) {
                bolusInfo
            }
        }

        var bolusInfo: some View {
            VStack {
                // Variables
                VStack(spacing: 3) {
                    HStack {
                        Text("Eventual Glucose").foregroundColor(.secondary)
                        let evg = state.units == .mmolL ? Decimal(state.evBG).asMmolL : Decimal(state.evBG)
                        Text(evg.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Target Glucose").foregroundColor(.secondary)
                        let target = state.units == .mmolL ? state.target.asMmolL : state.target
                        Text(target.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("ISF").foregroundColor(.secondary)
                        let isf = state.isf
                        Text(isf.formatted())
                        Text(state.units.rawValue + NSLocalizedString("/U", comment: "/Insulin unit"))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("ISF:")
                        Text("Insulin Sensitivity")
                    }.foregroundColor(.secondary).italic()
                    if state.percentage != 100 {
                        HStack {
                            Text("Percentage setting").foregroundColor(.secondary)
                            let percentage = state.percentage
                            Text(percentage.formatted())
                            Text("%").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Formula:")
                        Text("(Eventual Glucose - Target) / ISF")
                    }.foregroundColor(.secondary).italic().padding(.top, 5)
                }
                .font(.footnote)
                .padding(.top, 10)
                Divider()
                // Formula
                VStack(spacing: 5) {
                    let unit = NSLocalizedString(
                        " U",
                        comment: "Unit in number of units delivered (keep the space character!)"
                    )
                    let color: Color = (state.percentage != 100 && state.insulin > 0) ? .secondary : .blue
                    let fontWeight: Font.Weight = (state.percentage != 100 && state.insulin > 0) ? .regular : .bold
                    HStack {
                        Text(NSLocalizedString("Insulin recommended", comment: "") + ":").font(.callout)
                        Text(state.insulin.formatted() + unit).font(.callout).foregroundColor(color).fontWeight(fontWeight)
                    }
                    if state.percentage != 100, state.insulin > 0 {
                        Divider()
                        HStack { Text(state.percentage.formatted() + " % ->").font(.callout).foregroundColor(.secondary)
                            Text(
                                state.insulinRecommended.formatted() + unit
                            ).font(.callout).foregroundColor(.blue).bold()
                        }
                    }
                }
                // Warning
                if state.error, state.insulinRecommended > 0 {
                    VStack(spacing: 5) {
                        Divider()
                        Text("Warning!").font(.callout).bold().foregroundColor(.orange)
                        Text(alertString()).font(.footnote)
                        Divider()
                    }.padding(.horizontal, 10)
                }
                // Footer
                if !(state.error && state.insulinRecommended > 0) {
                    VStack {
                        Text(
                            "Carbs and previous insulin are included in the glucose prediction, but if the Eventual Glucose is lower than the Target Glucose, a bolus will not be recommended."
                        ).font(.caption2).foregroundColor(.secondary)
                    }.padding(20)
                }
                // Hide button
                VStack {
                    Button { presentInfo = false }
                    label: { Text("Hide") }.frame(maxWidth: .infinity, alignment: .center).font(.callout)
                        .foregroundColor(.blue)
                }.padding(.bottom, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray4))
                // .fill(Color(.systemGray).gradient)  // A more prominent pop-up, but harder to read
            )
        }

        // Localize the Oref0 error/warning strings. The default should never be returned
        private func alertString() -> String {
            switch state.errorString {
            case 1,
                 2:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is predicted to first drop down to ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) + state.minGuardBG
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) + " " + state.units
                    .rawValue + ", " +
                    NSLocalizedString(
                        "which is below your Threshold (",
                        comment: "Bolus pop-up / Alert string. Make translations concise!"
                    ) + state
                    .threshold.formatted() + " " + state.units.rawValue + ")"
            case 3:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is climbing slower than expected. Expected: ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) +
                    state.expectedDelta
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                    NSLocalizedString(". Climbing: ", comment: "Bolus pop-up / Alert string. Make translatons concise!") + state
                    .minDelta.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
            case 4:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is falling faster than expected. Expected: ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) +
                    state.expectedDelta
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                    NSLocalizedString(". Falling: ", comment: "Bolus pop-up / Alert string. Make translations concise!") + state
                    .minDelta.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
            case 5:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is changing faster than expected. Expected: ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) +
                    state.expectedDelta
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) +
                    NSLocalizedString(". Changing: ", comment: "Bolus pop-up / Alert string. Make translations concise!") + state
                    .minDelta.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
            case 6:
                return NSLocalizedString(
                    "Eventual Glucose > Target Glucose, but glucose is predicted to first drop down to ",
                    comment: "Bolus pop-up / Alert string. Make translations concise!"
                ) + state
                    .minPredBG
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) + " " + state
                    .units
                    .rawValue
            default:
                return "Ignore Warning..."
            }
        }
    }
}

// fix iOS 15 bug
struct ActivityIndicator: UIViewRepresentable {
    @Binding var isAnimating: Bool
    let style: UIActivityIndicatorView.Style

    func makeUIView(context _: UIViewRepresentableContext<ActivityIndicator>) -> UIActivityIndicatorView {
        UIActivityIndicatorView(style: style)
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context _: UIViewRepresentableContext<ActivityIndicator>) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}
