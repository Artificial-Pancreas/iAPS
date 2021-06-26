import SwiftUI

extension Bolus {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>
        @State private var isAddInsulinAlertPresented = false

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
                            Text(
                                formatter
                                    .string(from: viewModel.inslinRequired as NSNumber)! +
                                    NSLocalizedString(" U", comment: "Insulin unit")
                            ).foregroundColor(.secondary)
                        }.contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.amount = viewModel.inslinRecommended
                            }
                        HStack {
                            Text("Insulin recommended")
                            Spacer()
                            Text(
                                formatter
                                    .string(from: viewModel.inslinRequired as NSNumber)! +
                                    NSLocalizedString(" U", comment: "Insulin unit")
                            ).foregroundColor(.secondary)
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
                            .disabled(viewModel.amount <= 0)
                    }

                    Section {
                        if viewModel.waitForSuggestionInitial {
                            Button { viewModel.showModal(for: nil) }
                            label: { Text("Continue without bolus") }
                        } else {
                            Button { isAddInsulinAlertPresented = true }
                            label: { Text("Add insulin without actually bolusing") }
                                .disabled(viewModel.amount <= 0)
                        }
                    }
                }
            }
            .alert(isPresented: $isAddInsulinAlertPresented) {
                let amount = formatter
                    .string(from: viewModel.amount as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit")
                return Alert(
                    title: Text("Are you sure?"),
                    message: Text("Add \(amount) without bolusing"),
                    primaryButton: .destructive(
                        Text("Add"),
                        action: { viewModel.addWithoutBolus() }
                    ),
                    secondaryButton: .cancel()
                )
            }
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
