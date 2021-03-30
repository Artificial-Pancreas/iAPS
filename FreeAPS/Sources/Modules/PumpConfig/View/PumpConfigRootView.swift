import SwiftUI

extension PumpConfig {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section(header: Text("Model")) {
                    if let pumpState = viewModel.pumpState {
                        Button {
                            viewModel.setupPump = true
                        } label: {
                            HStack {
                                Image(uiImage: pumpState.image ?? UIImage()).padding()
                                Text(pumpState.name)
                            }
                        }
                    } else {
                        Button("Add Medtronic") { viewModel.addPump(.minimed) }
                        Button("Add Omnipod") { viewModel.addPump(.omnipod) }
                        Button("Add Simulator") { viewModel.addPump(.simulator) }
                    }
                }
            }
            .navigationTitle("Pump config")
            .navigationBarTitleDisplayMode(.automatic)
            .popover(isPresented: $viewModel.setupPump) {
                if let pumpManager = viewModel.provider.apsManager.pumpManager {
                    PumpSettingsView(pumpManager: pumpManager, completionDelegate: viewModel)
                } else {
                    PumpSetupView(
                        pumpType: viewModel.setupPumpType,
                        pumpInitialSettings: viewModel.initialSettings,
                        completionDelegate: viewModel,
                        setupDelegate: viewModel
                    )
                }
            }
        }
    }
}
