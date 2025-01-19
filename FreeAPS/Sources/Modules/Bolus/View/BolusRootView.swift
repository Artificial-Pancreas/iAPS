import SwiftUI
import Swinject

extension Bolus {
    struct RootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let fetch: Bool
        @StateObject var state = StateModel()

        @State private var keepForNextWiew: Bool = false

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        @FetchRequest(
            entity: Meals.entity(),
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        ) var meal: FetchedResults<Meals>

        var body: some View {
            if state.useCalc {
                if state.eventualBG {
                    DefaultBolusCalcRootView(
                        resolver: resolver,
                        waitForSuggestion: waitForSuggestion,
                        fetch: fetch,
                        state: state,
                        meal: meal,
                        mealEntries: mealEntries
                    )
                    .onDisappear {
                        if state.eventualBG {
                            state.notActive()
                        }
                    }
                } else {
                    AlternativeBolusCalcRootView(
                        resolver: resolver,
                        waitForSuggestion: waitForSuggestion,
                        fetch: fetch,
                        state: state,
                        meal: meal,
                        mealEntries: mealEntries
                    )
                    .onDisappear {
                        if !state.eventualBG {
                            state.notActive()
                        }
                    }
                }
            } else {
                cleanBolusView
            }
        }

        private var cleanBolusView: some View {
            Form {
                if fetch {
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
                            liveEditing: true
                        )
                        Text(!(state.amount > state.maxBolus) ? "U" : "😵").foregroundColor(.secondary)
                    }
                } header: { Text("Bolus") }

                Section {
                    if state.amount > 0 {
                        Button {
                            state.add()
                            keepForNextWiew = true
                        }
                        label: { Text(!(state.amount > state.maxBolus) ? "Enact bolus" : "Max Bolus exceeded!") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .disabled(state.amount > state.maxBolus)
                            .listRowBackground((state.amount <= state.maxBolus) ? Color(.systemBlue) : Color(.systemGray4))
                            .tint(.white)
                    } else {
                        Button {
                            state.hideModal()
                            keepForNextWiew = true
                        }
                        label: {
                            Text("Continue without bolus")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .onDisappear {
                if fetch, hasFatOrProtein, !keepForNextWiew, !state.useCalc {
                    state.delete(deleteTwice: true, meal: meal)
                } else if fetch, !keepForNextWiew, !state.useCalc {
                    state.delete(deleteTwice: false, meal: meal)
                }
                if !state.useCalc {
                    state.notActive()
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
                trailing: Button { state.hideModal() }
                label: { Text("Cancel") }
            )
        }

        private var hasFatOrProtein: Bool {
            ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        private var mealEntries: some View {
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
