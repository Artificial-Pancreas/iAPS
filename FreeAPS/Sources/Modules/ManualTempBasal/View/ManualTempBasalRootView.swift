import SwiftUI

extension ManualTempBasal {
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
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.rate, formatter: formatter, autofocus: true, cleanInput: true)
                        Text("U/hr").foregroundColor(.secondary)
                    }
                    Picker(selection: $viewModel.durationIndex, label: Text("Duration")) {
                        ForEach(0 ..< viewModel.durationValues.count) { index in
                            Text(
                                String(
                                    format: "%.0f h %02.0f min",
                                    viewModel.durationValues[index] / 60 - 0.1,
                                    viewModel.durationValues[index].truncatingRemainder(dividingBy: 60)
                                )
                            ).tag(index)
                        }
                    }
                }

                Section {
                    Button { viewModel.enact() }
                    label: { Text("Enact") }
                    Button { viewModel.cancel() }
                    label: { Text("Cancel Temp Basal") }
                }
            }
            .navigationTitle("Manual Temp Basal")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
