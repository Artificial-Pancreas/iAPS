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
                        DecimalTextField("U/hr", value: $viewModel.maxBasal, formatter: formatter)
                    }
                    HStack {
                        Text("Max Bolus")
                        DecimalTextField("U", value: $viewModel.maxBolus, formatter: formatter)
                    }
                }

                Section(header: Text("Duration of Insulin Action")) {
                    HStack {
                        Text("DIA")
                        DecimalTextField("hours", value: $viewModel.dia, formatter: formatter)
                    }
                }

                Section {
                    HStack {
                        if viewModel.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button { viewModel.save() }
                        label: {
                            Text(viewModel.syncInProgress ? "Saving..." : "Save on Pump")
                        }
                        .disabled(viewModel.syncInProgress)
                    }
                }
            }
            .navigationTitle("Pump Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
