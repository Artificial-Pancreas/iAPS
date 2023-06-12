import SwiftUI
import Swinject

extension Bolus {
    struct RootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let manualBolus: Bool
        @StateObject var state = StateModel()
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
            .alert(isPresented: $displayError) {
                Alert(
                    title: Text("Warning!"),
                    message: Text("\n" + NSLocalizedString(state.errorString, comment: "") + NSLocalizedString(
                        "\n\nTap 'Add' to continue with selected amount.",
                        comment: "Alert text to confirm bolus amount to add"
                    )),
                    primaryButton: .destructive(
                        Text("Add"),
                        action: {
                            state.amount = state.insulinRecommended
                            displayError = false
                        }
                    ),
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                configureView {
                    state.waitForSuggestionInitial = waitForSuggestion
                    state.waitForSuggestion = waitForSuggestion
                    state.manual = manualBolus
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
                        let fractionDigit = state.units == .mmolL ? 1 : 0
                        Text(evg.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigit))))
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Target Glucose").foregroundColor(.secondary)
                        let target = state.units == .mmolL ? state.target.asMmolL : state.target
                        let fractionDigit = state.units == .mmolL ? 1 : 0
                        Text(target.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigit))))
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
                    Text("(Eventual Glucose - Target) / ISF =").font(.callout).italic()
                    let color: Color = (state.percentage != 100 && state.insulin > 0) ? .secondary : .blue
                    let fontWeight: Font.Weight = (state.percentage != 100 && state.insulin > 0) ? .regular : .bold
                    HStack {
                        Text(" = ").font(.callout)
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
                VStack {
                    Divider()
                    if state.error, state.insulinRecommended > 0 {
                        Text("Warning!").font(.callout).foregroundColor(.orange).bold()
                        Text(NSLocalizedString(state.errorString, comment: "")).font(.caption)
                        Divider()
                    }
                }.padding(.horizontal, 10)
                // Footer. Warning string .
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
            )
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
