import SwiftUI

extension PumpSettingsEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Delivery limits")) {
                    HStack {
                        Text("Max Basal")
                        DecimalTextField("hours", value: $viewModel.maxBasal, formatter: formatter)
                    }
                    HStack {
                        Text("Max Bolus")
                        DecimalTextField("U/hour", value: $viewModel.maxBolus, formatter: formatter)
                    }
                }

                Section(header: Text("Duration of Insulin Action")) {
                    HStack {
                        Text("DIA")
                        DecimalTextField("hours", value: $viewModel.dia, formatter: formatter)
                    }
                }

                Section {
                    Button { viewModel.save() }
                    label: {
                        Text(viewModel.syncInProgress ? "Saving..." : "Save on Pump")
                    }
                    .disabled(viewModel.syncInProgress)
                }
            }
            .navigationTitle("Pump Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
