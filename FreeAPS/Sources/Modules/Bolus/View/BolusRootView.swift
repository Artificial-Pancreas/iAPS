import SwiftUI
import Swinject

extension Bolus {
    struct RootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        // @Injected() var apsManager: APSManager!  //needed for rounding bolus to pump specifics (line 40)
        @StateObject var state = StateModel()
        @State private var isAddInsulinAlertPresented = false
        @State private var showInfo = false
        @State private var insulinWholeCOB: Decimal = 0
        @State private var showIobCalc: Decimal = 0
        @State private var deltaBg: Decimal = 0
        @State private var bgFactor: Decimal = 0
        @State private var wholeCOB: Decimal = 0
        @State private var fifteenMinDelta: Decimal = 0
        @State private var FactorfifteenMinDelta: Decimal = 0
        @State private var InsulinfifteenMinDelta: Decimal = 0
        @State private var wholeCalc: Decimal = 0
        @State private var roundedWholeCalc: Decimal = 0
        @State private var bgDependentInsulinCorrection: Decimal = 0
        @State private var useCorrectionFactor: Bool = false {
            didSet {
                insulinCalculated = calculateInsulin()
            }
        }

        @State private var superBolus: Bool = false {
            didSet {
                insulinCalculated = calculateInsulin()
            }
        }

        @State private var insulinCalculated: Decimal = 0

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        // BEGINNING OF CALCULATIONS FOR THE BOLUS CALCULATOR
        // ......
        // ......

        func calculateInsulin() -> Decimal {
            // more or less insulin because of bg trend in the last 15 minutes
            fifteenMinDelta = state.DeltaBZ
            FactorfifteenMinDelta = (state.suggestion?.isf ?? 0) / fifteenMinDelta
            InsulinfifteenMinDelta = (1 / FactorfifteenMinDelta)

            // determine how much insulin is needed for the current bg

            deltaBg = state.BZ - (state.suggestion?.current_target ?? 0)
            bgFactor = (state.suggestion?.isf ?? 0) / deltaBg
            bgDependentInsulinCorrection = (1 / bgFactor)

            // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
            wholeCOB = (state.suggestion?.cob ?? 0) + state.Carbs
            insulinWholeCOB = wholeCOB / state.cRatio

            // determine how much the calculator reduces/ increases the bolus because of IOB
            showIobCalc = (-1) * (state.suggestion?.iob ?? 0)

            // adding all the factors together
            // add a calc for the case that no InsulinfifteenMinDelta is available
            if state.DeltaBZ != 0 {
                wholeCalc = (bgDependentInsulinCorrection + showIobCalc + insulinWholeCOB + InsulinfifteenMinDelta)
            } else {
                if state.BZ == 0 {
                    wholeCalc = (showIobCalc + insulinWholeCOB)
                } else {
                    wholeCalc = (bgDependentInsulinCorrection + showIobCalc + insulinWholeCOB)
                }
            }
            let doubleWholeCalc = Double(wholeCalc)
            roundedWholeCalc = Decimal(round(10 * doubleWholeCalc) / 10)

            // dermine fraction of whole bolus in % using state.overrideFactor......should also be made adjustable by the user
            let fraction = (state.overrideFactor / 100)

            let normalCalculation = wholeCalc * fraction

            if useCorrectionFactor {
                // if meal is fatty bolus will be reduced ....could be made adjustable later
                insulinCalculated = normalCalculation * 0.7
            } else if superBolus {
                // adding two hours worth of basal to the bolus.....hard coded just for my case
                insulinCalculated = normalCalculation + 1.2
            } else {
                insulinCalculated = normalCalculation
            }
            insulinCalculated = max(insulinCalculated, 0)
            return insulinCalculated
        }

        // ......
        // ......
        // END OF CALCULATIONS FOR THE BOLUS CALCULATOR

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Blutzucker")

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
                            insulinCalculated = calculateInsulin()
                        }
                        Text(
                            NSLocalizedString("mg/dL", comment: "mg/dL")
                        ).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())

                    HStack {
                        Text("Kohlenhydrate")
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.Carbs,
                            formatter: formatter,
                            autofocus: false,
                            cleanInput: true
                        )
                        .onChange(of: state.Carbs) { newValue in
                            if newValue > 200 {
                                state.Carbs = 200 // ensure that user can not input more than 200g of carbs accidentally
                            }
                            insulinCalculated = calculateInsulin()
                        }
                        Text(
                            NSLocalizedString("g", comment: "grams")
                        ).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Anteil")
                        Button(action: {
                            showInfo.toggle()
                            insulinCalculated = calculateInsulin()
                        }, label: {
                            Image(systemName: "info.circle")
                        })
                            .buttonStyle(PlainButtonStyle())
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.overrideFactor,
                            formatter: formatter,
                            autofocus: false,
                            cleanInput: true
                        )
                        .onChange(of: state.overrideFactor) { newValue in
                            if newValue > 100 {
                                state
                                    .overrideFactor =
                                    100 // ensure that user can not input more than 100% of bolus accidentally
                            }
                            insulinCalculated = calculateInsulin()
                        }
                        Text(
                            NSLocalizedString("%", comment: "%")
                        ).foregroundColor(.secondary)
                    }
                }

                if showInfo {
                    Section {
                        HStack {
                            Text("BG").foregroundColor(.gray)
                            Spacer()
                            Text(
                                formatter
                                    .string(from: state.BZ as NSNumber)! + NSLocalizedString(" mg/dL", comment: "mg/dL")
                            ).foregroundColor(.gray)
                            Spacer()
                            Text(
                                (formatter.string(from: bgDependentInsulinCorrection as NSNumber) ?? "") +
                                    NSLocalizedString(" IE", comment: "IE")
                            ).foregroundColor(.gray)
                        }.contentShape(Rectangle())
                        HStack {
                            Text("Trend").foregroundColor(.gray)
                            Spacer()
                            Text(
                                formatter
                                    .string(from: state.DeltaBZ as NSNumber)! + NSLocalizedString(" mg/dL", comment: "mg/dL")
                            ).foregroundColor(.gray)
                            Spacer()
                            Text(
                                (formatter.string(from: InsulinfifteenMinDelta as NSNumber) ?? "") +
                                    NSLocalizedString(" IE", comment: "IE")
                            ).foregroundColor(.gray)
                        }.contentShape(Rectangle())
                        HStack {
                            Text("IOB").foregroundColor(.gray)
                            Spacer()
                            Text(
                                (numberFormatter.string(from: (state.suggestion?.iob ?? 0) as NSNumber) ?? "0") +
                                    NSLocalizedString(" U", comment: "Insulin unit")
                            ).foregroundColor(.gray)
                            Spacer()
                            Text(
                                (formatter.string(from: showIobCalc as NSNumber) ?? "") +
                                    NSLocalizedString(" IE", comment: "IE")
                            ).foregroundColor(.gray)
                        }.contentShape(Rectangle())
                        HStack {
                            Text("COB").foregroundColor(.gray)
                            Spacer()
                            Text(
                                (formatter.string(from: wholeCOB as NSNumber) ?? "") +
                                    NSLocalizedString(" g", comment: "g carbs")
                            ).foregroundColor(.gray)
                            Spacer()
                            Text(
                                (formatter.string(from: insulinWholeCOB as NSNumber) ?? "") +
                                    NSLocalizedString(" IE", comment: "IE")
                            ).foregroundColor(.gray)
                        }.contentShape(Rectangle())
                        HStack {
                            Text("CR").foregroundColor(.gray)
                            Spacer()
                            Text(
                                formatter
                                    .string(from: state.cRatio as NSNumber)! + NSLocalizedString(" g/U", comment: "g/U")
                            ).foregroundColor(.gray)
                        }.contentShape(Rectangle())
                        HStack {
                            Text("ISF").foregroundColor(.gray)
                            Spacer()
                            Text(
                                (numberFormatter.string(from: (state.suggestion?.isf ?? 0) as NSNumber) ?? "0") +
                                    NSLocalizedString(" mg/dL/U", comment: "mg/dL/U")
                            ).foregroundColor(.gray)
                        }.contentShape(Rectangle())
                        HStack {
                            Text("Ziel").foregroundColor(.gray)
                            Spacer()
                            Text(
                                (numberFormatter.string(from: (state.suggestion?.current_target ?? 0) as NSNumber) ?? "0") +
                                    NSLocalizedString(" mg/dL", comment: "mg/dL")
                            ).foregroundColor(.gray)
                        }.contentShape(Rectangle())
                        HStack {
                            Text("Anteil").foregroundColor(.gray)
                            Spacer()
                            Text(
                                formatter
                                    .string(from: state.overrideFactor as NSNumber)! +
                                    NSLocalizedString(" % von ", comment: "Percentage") + String(describing: roundedWholeCalc)
                            ).foregroundColor(.gray)
                        }
                    }
                    Section {
                        Toggle(isOn: $useCorrectionFactor) {
                            Text("Fettig").foregroundColor(.yellow)
                        }.onChange(of: useCorrectionFactor) { _ in
                            insulinCalculated = calculateInsulin()
                        }
                        Toggle(isOn: $superBolus) {
                            Text("Super Bolus").foregroundColor(.purple)
                        }.onChange(of: superBolus) { _ in
                            insulinCalculated = calculateInsulin()
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Empfohlener Bolus")
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
                                    .font(.system(size: 22))
                            })
                                .disabled(state.amount <= 0)
                                .buttonStyle(PlainButtonStyle())
                                .padding(.trailing, 10)
                        }
                    }
                }

                Section {
                    HStack(alignment: .center) {
                        Spacer()
                        Button { state.add() }
                        label: { Text("Enact bolus")
                            .foregroundColor(.white)
                            .padding(.horizontal, 100)
                            .padding(.vertical, 15)
                            .background(Color.blue)

                            .cornerRadius(15)
                            .contentShape(Rectangle())
                        }
                        .disabled(state.amount <= 0)
                        Spacer()
                    }
                }
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
                }
            }
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
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

