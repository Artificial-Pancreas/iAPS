import SwiftUI

extension AddCarbs {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        var body: some View {
            Form {
                if let carbsReq = viewModel.carbsRequired {
                    Section {
                        HStack {
                            Text("Carbs required")
                            Spacer()
                            Text(formatter.string(from: carbsReq as NSNumber)! + " g")
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.carbs, formatter: formatter, autofocus: true, cleanInput: true)
                        Text("grams").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $viewModel.date)
                }

                Section {
                    Button { viewModel.add() }
                    label: { Text("Add") }
                        .disabled(viewModel.carbs <= 0)
                }
            }
            .navigationTitle("Add Carbs")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
