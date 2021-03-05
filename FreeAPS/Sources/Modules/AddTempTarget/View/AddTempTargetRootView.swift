import SwiftUI

extension AddTempTarget {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Bottom target")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.low, formatter: formatter, autofocus: true, cleanInput: true)
                        Text(viewModel.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Top target")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.high, formatter: formatter, cleanInput: true)
                        Text(viewModel.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        DecimalTextField("0", value: $viewModel.duration, formatter: formatter, cleanInput: true)
                        Text("minutes").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $viewModel.date)
                }

                Section {
                    Button { viewModel.add() }
                    label: { Text("Continue") }
                }
            }
            .navigationTitle("Add Temp Target")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
