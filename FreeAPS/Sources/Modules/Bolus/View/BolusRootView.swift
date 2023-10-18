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
        @State var insulinCalculated: Decimal = 0

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
                            if newValue > 200 {
                                state.Carbs = 200 // ensure that user can not input more than 200g of carbs accidentally
                            }
                            insulinCalculated = state.calculateInsulin()
                        }
                        Text(
                            NSLocalizedString("g", comment: "grams")
                        ).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Fraction")
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.overrideFactor,
                            formatter: formatter,
                            autofocus: false,
                            cleanInput: true
                        )
                        .onChange(of: state.overrideFactor) { newValue in
                            // ensure that user can not input more than 100% of bolus accidentally
                            if newValue > 100 {
                                state.overrideFactor = 100
                            }
                            insulinCalculated = state.calculateInsulin()
                        }
                        Text(
                            NSLocalizedString("%", comment: "%")
                        ).foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    withAnimation {
                        showInfo.toggle()
                    }
                    insulinCalculated = state.calculateInsulin()
                }, label: {
                    Image(systemName: "info.circle")
                    Text("Calculations")
                })
                    .foregroundStyle(.blue)
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                                    .font(.system(size: 25))
                            })
                                .disabled(state.amount <= 0)
                                .buttonStyle(PlainButtonStyle())
                                .padding(.trailing, 10)
                        }
                    }
                }

                Button(action: {
                    state.add()
                }) {
                    Text("Enact bolus")
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(state.amount <= 0)

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
                .popover(isPresented: $showInfo, content: {
                    PopUpView()
                        .padding()
                })
                .onAppear {
                    configureView {
                        state.waitForSuggestionInitial = waitForSuggestion
                        state.waitForSuggestion = waitForSuggestion
                        insulinCalculated = state.calculateInsulin()
                    }
                }
                .navigationTitle("Enact Bolus")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: state.hideModal))
            }
        }
    }

    struct PopUpView: View {
        @StateObject var state = StateModel()
        @Environment(\.dismiss) var dismiss

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

        var body: some View {
            NavigationView {
                VStack {
                    VStack {
                        HStack {
                            Text("Carb Ratio: ")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(
                                formatter.string(from: state.cRatio as NSNumber)! + NSLocalizedString(" g/U", comment: "g/U")
                            )
                        }
                        HStack {
                            Text("ISF: ")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(
                                (numberFormatter.string(from: (state.suggestion?.isf ?? 0) as NSNumber) ?? "0") +
                                    NSLocalizedString(" mg/dL/U", comment: "mg/dL/U")
                            )
                        }
                        HStack {
                            Text("Target: ")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(
                                (numberFormatter.string(from: (state.suggestion?.current_target ?? 0) as NSNumber) ?? "0") +
                                    NSLocalizedString(" mg/dL", comment: "mg/dL")
                            )
                        }
                    }
                    .padding()

                    VStack {
                        CalculationInfo(
                            title: "BG",
                            value: state.BZ as NSNumber,
                            unit: " mg/dl",
                            comment1: "mg/dl",
                            calculationInfo: state.bgDependentInsulinCorrection as NSNumber,
                            calcInfoUnit: " IE",
                            comment2: "IE"
                        )
                        CalculationInfo(
                            title: "Trend",
                            value: state.DeltaBZ as NSNumber,
                            unit: " mg/dl",
                            comment1: "mg/dl",
                            calculationInfo: state.InsulinfifteenMinDelta as NSNumber,
                            calcInfoUnit: " IE",
                            comment2: "IE"
                        )
                        CalculationInfo(
                            title: "IOB",
                            value: state.BZ as NSNumber,
                            unit: " IE",
                            comment1: "IE",
                            calculationInfo: (state.suggestion?.iob ?? 0) as NSNumber,
                            calcInfoUnit: " IE",
                            comment2: "IE"
                        )
                        CalculationInfo(
                            title: "COB",
                            value: state.wholeCalc as NSNumber,
                            unit: " g",
                            comment1: "IE",
                            calculationInfo: state.insulinWholeCOB as NSNumber,
                            calcInfoUnit: " IE",
                            comment2: "IE"
                        )
                        Divider()
                            .fontWeight(.bold)
                        CalculationInfo(
                            title: "Result",
                            value: state.overrideFactor as NSNumber,
                            unit: " % von " + String(describing: state.roundedWholeCalc) + String(describing: " IE = "),
                            comment1: "",
                            calculationInfo: state.insulinCalculated as NSNumber,
                            calcInfoUnit: " IE",
                            comment2: "IE"
                        )
                        .fontWeight(.bold)
                    }
                    .padding()

                    Spacer()
                }
                .navigationTitle("Calculations")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading:
                    Button(action: {
                        dismiss()
                    }, label: {
                        Text("Close")
                    })
                )
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
