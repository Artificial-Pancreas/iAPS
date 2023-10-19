import SwiftUI
import Swinject

extension Bolus {
    struct RootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        @StateObject var state = StateModel()

        @State private var isAddInsulinAlertPresented = false
        @State private var showInfo = false
        @State private var carbsWarning = false
        @State var insulinCalculated: Decimal = 0

        @Injected() var settings: SettingsManager!

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
                bolusInfo
            }
        }

        // my bolusInfo variable/popup
        var bolusInfo: some View {
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
                            Text(iob.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let iobCalc = state.showIobCalc
                            Text(iobCalc.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
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
                            Text(trendInsulin.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
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
                            Text(insulinCob.formatted() + NSLocalizedString(" U", comment: "Insulin unit"))
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

        // here could follow jons variable/popup
        // ....
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
