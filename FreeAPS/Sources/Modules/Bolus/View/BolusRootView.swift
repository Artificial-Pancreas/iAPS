import SwiftUI
import Swinject

extension Bolus {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        @EnvironmentObject private var mainState: Main.StateModel

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

        private func format(_ number: Decimal) -> String {
            mealFormatter.string(from: number as NSNumber) ?? ""
        }

        /// `meal`: handed over by Add Meal (pushed on its navigation stack), stored only by this view
        init(
            resolver: Resolver,
            waitForSuggestion: Bool,
            meal: MealDraft?
        ) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(
                resolver: resolver,
                waitForSuggestion: waitForSuggestion,
                meal: meal
            ))
        }

        var body: some View {
            calculator
                // the system back button (to Add Meal) only when nothing is being stored
                .navigationBarBackButtonHidden(state.committing)
                // again after a cancelled back swipe (which may or may not have fired onDisappear): re-arms, idempotent.
                // No onDisappear: a pop (Add Meal clears the swipe block) or the modal closing ends this Bolus
                .onAppear {
                    state.viewActive()
                    // no swipe-down while a meal is pending (a pushed view's interactiveDismissDisabled may not reach the sheet)
                    if let meal = state.meal, !state.closed { mainState.bolusMealPending = meal.id }
                    state.start()
                }
        }

        @ViewBuilder private var calculator: some View {
            if state.useCalc {
                if state.eventualBG {
                    DefaultBolusCalcRootView(
                        resolver: resolver,
                        mealEntries: mealEntries
                    )
                    .environmentObject(state)
                } else {
                    AlternativeBolusCalcRootView(
                        resolver: resolver,
                        mealEntries: mealEntries
                    )
                    .environmentObject(state)
                }
            } else {
                cleanBolusView
            }
        }

        private var cleanBolusView: some View {
            Form {
                if state.meal != nil {
                    Section {
                        mealEntries
                    } header: { Text("Meal Summary") }
                }

                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.amount,
                            formatter: formatter,
                            autofocus: true,
                            liveEditing: true
                        )
                        Text(!(state.amount > state.maxBolus) ? "U" : "😵").foregroundColor(.secondary)
                    }
                } header: { Text("Bolus") }

                Section {
                    if state.amount > 0 {
                        Button {
                            state.enact()
                        }
                        label: {
                            Bolus.enactLabel(
                                !(state.amount > state.maxBolus) ? "Enact bolus" : "Max Bolus exceeded!",
                                committing: state.committing
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(state.amount > state.maxBolus || state.committing)
                        .listRowBackground(
                            (state.amount <= state.maxBolus && !state.committing) ? Color(.systemBlue) : Color(.systemGray4)
                        )
                        .tint(.white)
                    } else {
                        Button {
                            state.saveWithoutBolus()
                        }
                        label: {
                            Text("Continue without bolus")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(state.committing)
                    }
                }
            }
            .interactiveDismissDisabled(state.meal != nil)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Bolus.toolbar(state) }
        }

        private var mealEntries: some View {
            let meal = state.meal?.entry
            return VStack {
                if let carbs = meal?.carbs, carbs != 0 {
                    HStack {
                        Text("Carbs")
                        Spacer()
                        Text(format(carbs))
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let fat = meal?.fat, fat != 0 {
                    HStack {
                        Text("Fat")
                        Spacer()
                        Text(format(fat))
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let protein = meal?.protein, protein != 0 {
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text(format(protein))
                        Text("g")
                    }.foregroundColor(.secondary)
                }
                if let note = meal?.note, note != "" {
                    HStack {
                        Text("Note")
                        Spacer()
                        Text(note)
                    }.foregroundColor(.secondary)
                }
            }
        }
    }
}

extension Bolus {
    /// Leading "‹ Meal" (Bolus from Home only; with a meal the system back button returns to Add Meal) and Cancel.
    /// Cancel with a meal closes the sheet and discards the meal
    @MainActor @ToolbarContentBuilder static func toolbar(_ state: StateModel) -> some ToolbarContent {
        if state.meal == nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    state.addMeal()
                }
                label: {
                    HStack {
                        Image(systemName: "chevron.backward")
                        Text("Meal")
                    }
                }
                .disabled(state.committing)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                state.cancel()
            }
            label: { Text("Cancel") }
                .disabled(state.committing)
        }
    }

    /// The Enact button's label: while the bolus is being committed (from the tap until the pump has answered) a
    /// spinner and "Starting bolus" replace the title, so the tap visibly registered
    @MainActor @ViewBuilder static func enactLabel(_ title: LocalizedStringKey, committing: Bool) -> some View {
        if committing {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text(NSLocalizedString("Starting bolus", comment: "Bolus progress bar title while the pump starts the bolus"))
            }
        } else {
            Text(title)
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
