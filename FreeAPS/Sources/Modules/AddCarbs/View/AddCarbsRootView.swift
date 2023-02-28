import SwiftUI
import Swinject

extension AddCarbs {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        var body: some View {
            Form {
                if let carbsReq = state.carbsRequired {
                    Section {
                        HStack {
                            Text("Carbs required")
                            Spacer()
                            Text(formatter.string(from: carbsReq as NSNumber)! + " g")
                        }
                    }
                }
                Section {
                    Section {
                        HStack {
                            Text("Carbs").fontWeight(.semibold)
                            Spacer()
                            DecimalTextField("0", value: $state.carbs, formatter: formatter, autofocus: true, cleanInput: true)
                            Text("grams").foregroundColor(.secondary)
                        }.padding(.vertical)

                        // MARK: Adding Protein and Fat. Test

                        if state.useFPU {
                            HStack {
                                Text("Protein").foregroundColor(.loopRed).fontWeight(.thin)
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.protein,
                                    formatter: formatter,
                                    autofocus: false,
                                    cleanInput: true
                                ).foregroundColor(.loopRed)
                                Text("grams").foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Fat").foregroundColor(.loopYellow).fontWeight(.thin)
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.fat,
                                    formatter: formatter,
                                    autofocus: false,
                                    cleanInput: true
                                )
                                Text("grams").foregroundColor(.secondary)
                            }
                        }
                        DatePicker("Date", selection: $state.date)
                    }
                }
                Section {
                    Button { state.add() }
                    label: { Text("Add") }
                        .disabled(state.carbs <= 0 && state.fat <= 0 && state.protein <= 0)
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Add Carbs")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
        }
    }
}
