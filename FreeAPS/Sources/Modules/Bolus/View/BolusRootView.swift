import SwiftUI

extension Bolus {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.amount, formatter: formatter, autofocus: true, cleanInput: true)
                        Text("U").foregroundColor(.secondary)
                    }
                }

                Section {
                    Button { viewModel.add() }
                    label: { Text("Enact") }
                }
            }
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
