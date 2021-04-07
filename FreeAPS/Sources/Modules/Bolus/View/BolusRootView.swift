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
                Section(header: Text("Recommendation")) {
                    if viewModel.waitForSuggestion {
                        HStack {
                            Text("Wait please").foregroundColor(.secondary)
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        HStack {
                            Text("Insulin required").foregroundColor(.secondary)
                            Spacer()
                            Text(formatter.string(from: viewModel.inslinRequired as NSNumber)! + " U").foregroundColor(.secondary)
                        }.contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.amount = viewModel.inslinRecommended
                            }
                        HStack {
                            Text("Insulin recommended")
                            Spacer()
                            Text(formatter.string(from: viewModel.inslinRecommended as NSNumber)! + " U")
                        }.contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.amount = viewModel.inslinRecommended
                            }
                    }
                }

                if !viewModel.waitForSuggestion {
                    Section(header: Text("Bolus")) {
                        HStack {
                            Text("Amount")
                            Spacer()
                            DecimalTextField(
                                "0",
                                value: $viewModel.amount,
                                formatter: formatter,
                                autofocus: true,
                                cleanInput: true
                            )
                            Text("U").foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Button { viewModel.add() }
                        label: { Text("Enact bolus") }

                        if viewModel.waitForSuggestionInitial {
                            Button { viewModel.showModal(for: nil) }
                            label: { Text("Continue without bolus") }
                        } else {
                            Button { viewModel.addWithoutBolus() }
                            label: { Text("Add insulin without actual bolusing") }
                        }
                    }
                }
            }
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
