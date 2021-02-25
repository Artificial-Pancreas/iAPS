import SwiftUI

extension PumpConfig {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section(header: Text("Pump")) {
                    if let pumpState = viewModel.pumpState {
                        HStack {
                            Image(uiImage: pumpState.image ?? UIImage()).padding()
                            Text(pumpState.name)
                        }
                    } else {
                        Button("Add Medtronic") { viewModel.addPump(.minimed) }
                        Button("Add Omnipod") { viewModel.addPump(.omnipod) }
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .principal) { Text("Pump Config") } }
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
            .navigationBarTitleDisplayMode(.inline)
            .popover(isPresented: $viewModel.setupPump) {
                PumpSetupView(
                    pumpType: viewModel.setupPumpType,
                    pumpInitialSettings: .default,
                    completionDelegate: viewModel,
                    setupDelegate: viewModel
                )
            }
        }
    }
}
