import Charts
import CoreData
import SwiftUI
import Swinject

extension Bolus {
    struct DefaultBolusCalcRootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let fetch: Bool

        @StateObject var state = StateModel()

        let meal: FetchedResults<Meals>
        let mealEntries: any View

        @State private var isAddInsulinAlertPresented = false
        @State private var presentInfo = false
        @State private var displayError = false
        @State private var keepForNextWiew: Bool = false
        @State private var remoteBolusAlert: Alert?
        @State private var isRemoteBolusAlertPresented: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @FocusState private var isFocused: Bool

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var loopFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = state.units == .mmolL ? 1 : 0
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
                    } else if state.predictions != nil {
                        predictionChart
                    } else {
                        Text("No Predictions. Failed loop suggestion.").frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if fetch {
                    Section {
                        mealEntries.asAny()
                    }
                }

                Section {
                    if state.waitForSuggestion {
                        HStack {
                            Text("Wait please").foregroundColor(.secondary)
                            Spacer()
                            ActivityIndicator(isAnimating: .constant(true), style: .medium) // fix iOS 15 bug
                        }
                    } else if state.suggestion != nil {
                        HStack {
                            Button(action: {
                                presentInfo.toggle()
                            }, label: {
                                Image(systemName: "info.bubble")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(colorScheme == .light ? .black : .white, .blue)
                                    .font(.infoSymbolFont)
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
                                .onChange(of: state.useFattyMealCorrectionFactor) {
                                    state.insulinCalculated = state.calculateInsulin()
                                }
                            }
                        }

                        HStack {
                            Text("Insulin recommended")
                            Spacer()

                            Text(
                                formatter
                                    .string(from: state.insulinCalculated as NSNumber) ?? "" +
                                    NSLocalizedString(" U", comment: "Insulin unit")
                            ).foregroundColor(.secondary)
                                .onTapGesture {
                                    state.amount = state.insulinCalculated
                                }
                        }.contentShape(Rectangle())
                    }
                    HStack {
                        Text("Amount")
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.amount,
                            formatter: formatter,
                            liveEditing: true
                        )
                        Text(!(state.amount > state.maxBolus) ? "U" : "😵").foregroundColor(.secondary)
                    }
                    .focused($isFocused)
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
                        label: { Text(!(state.amount > state.maxBolus) ? "Enact bolus" : "Max Bolus exceeded!") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .disabled(disabled)
                            .listRowBackground(!disabled ? Color(.systemBlue) : Color(.systemGray4))
                            .tint(.white)
                    }
                    footer: {
                        if (-1 * state.loopDate.timeIntervalSinceNow / 60) > state.loopReminder, let string = state.lastLoop() {
                            Text(NSLocalizedString(string, comment: "Bolus View footer"))
                                .padding(.top, 20).multilineTextAlignment(.center)
                                .foregroundStyle(.orange)
                        }
                    }
                    .alert(isPresented: $isRemoteBolusAlertPresented) {
                        remoteBolusAlert!
                    }
                }

                if state.amount <= 0 {
                    Section {
                        Button {
                            keepForNextWiew = true
                            state.save()
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
                    footer: {
                        if abs(state.loopDate.timeIntervalSinceNow / 60) > state.loopReminder, let string = state.lastLoop() {
                            Text(NSLocalizedString(string, comment: "Bolus View footer"))
                                .padding(.top, 20).multilineTextAlignment(.center)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
            .compactSectionSpacing()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear {
                configureView {
                    state.viewActive()
                    state.waitForCarbs = fetch
                    state.waitForSuggestionInitial = waitForSuggestion
                    state.waitForSuggestion = waitForSuggestion
                }
            }
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button {
                    keepForNextWiew = state.carbsView(fetch: fetch, hasFatOrProtein: hasFatOrProtein, mealSummary: meal)
                }
                label: {
                    HStack {
                        Image(systemName: "chevron.backward")
                        Text("Meal")
                    }
                },
                trailing: Button {
                    state.hideModal()
                    state.notActive()
                    if fetch { state.apsManager.determineBasalSync() }
                }
                label: { Text("Cancel") }
            )
            .popup(isPresented: presentInfo, alignment: .bottom, direction: .bottom, type: .default) {
                formulasView()
            }
        }

        var disabled: Bool {
            state.amount <= 0 || state.amount > state.maxBolus
        }

        var predictionChart: some View {
            ZStack {
                PredictionView(
                    predictions: $state.predictions, units: $state.units, eventualBG: $state.evBG,
                    useEventualBG: $state.eventualBG, target: $state.target,
                    displayPredictions: $state.displayPredictions, currentGlucose: $state.currentBG
                )
            }
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
                state.backToCarbsView(override: false, editMode: true)
            } else {
                state.backToCarbsView(override: true, editMode: false)
            }
        }

        @ViewBuilder private func formulasView() -> some View {
            let entries = [
                Formulas(
                    variable: NSLocalizedString("Eventual Glucose", comment: ""),
                    value: glucoseFormatter.string(for: state.evBG) ?? "",
                    unit: state.units.rawValue,
                    color: .primary
                ),
                Formulas(
                    variable: NSLocalizedString("Target Glucose", comment: ""),
                    value: state.target.formatted(),
                    unit: state.units.rawValue,
                    color: .primary
                ),
                Formulas(
                    variable: NSLocalizedString("ISF", comment: ""),
                    value: state.isf.formatted(),
                    unit: state.units.rawValue + NSLocalizedString("/U", comment: "Insulin unit"),
                    color: .primary
                ),
                Formulas(
                    variable: NSLocalizedString("Factor", comment: ""),
                    value: state.fraction.formatted(),
                    unit: "",
                    color: .primary
                )
            ]

            VStack {
                Grid(verticalSpacing: 3) {
                    ForEach(entries.dropLast()) { entry in
                        GridRow {
                            Text(entry.variable).foregroundStyle(.secondary)
                            Text(entry.value).foregroundStyle(entry.color)
                            Text(entry.unit).foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.top, 10)

                    HStack {
                        Text("Formula:")
                        Text("(Eventual Glucose - Target) / ISF")
                    }.foregroundStyle(.secondary).italic().padding(.vertical, 10)
                    Divider()
                    // Formula
                    VStack(spacing: 5) {
                        if state.insulin > 0 {
                            let unit = NSLocalizedString(
                                " U",
                                comment: "Unit in number of units delivered (keep the space character!)"
                            )
                            let color: Color = (state.fraction != 1 && state.insulin > 0) ? .secondary : .blue
                            let fontWeight: Font.Weight = (state.fraction != 1 && state.insulin > 0) ? .regular : .bold
                            HStack {
                                Text(NSLocalizedString("Insulin recommended", comment: "") + ":")
                                Text(formatter.string(for: state.insulin) ?? "" + unit).foregroundStyle(color)
                            }.padding(.vertical, 10)
                            if state.fraction != 1, state.insulin > 0 {
                                Divider()
                                HStack {
                                    Text((entries.last?.variable ?? "") + " " + (entries.last?.value ?? "") + "  ->")
                                        .foregroundStyle(.secondary)
                                    Text(
                                        state.insulinCalculated.formatted() + unit
                                    ).fontWeight(fontWeight).font(.title3).foregroundStyle(.blue).bold()
                                }
                            }
                        }
                        // Footer
                        VStack {
                            if state.evBG < state.target {
                                Text(
                                    "Eventual Glucose is lower than your target glucose. No insulin recommended."
                                ).foregroundStyle(.red)
                            } else if state.minimumPrediction, state.minPredBG < state.threshold {
                                Text(
                                    "Minimum Predicted Glucose is lower than your glucose threshold. No insulin recommended."
                                ).foregroundStyle(.red)
                            } else {
                                Text(
                                    "Carbs and previous insulin are included in the eventual glucose prediction."
                                ).foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                        .padding(20)
                        // Hide button
                        VStack {
                            Button { presentInfo = false }
                            label: { Text("Hide") }.frame(maxWidth: .infinity, alignment: .center)
                                .tint(.blue)
                        }.padding(.bottom, 10)
                    }
                }
                .padding(20)
                .dynamicTypeSize(...DynamicTypeSize.small)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray4))
            )
        }
    }
}
