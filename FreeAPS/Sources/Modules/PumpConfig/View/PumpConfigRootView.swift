import SwiftUI

extension PumpConfig {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section(header: Text("Devices")) {
                    ForEach(viewModel.rileyDisplayStates.indexed(), id: \.1.id) { index, state in
                        Toggle(isOn: self.$viewModel.rileyDisplayStates[index].connected) {
                            HStack {
                                Text(state.name)
                                Spacer()
                                Text(state.rssi.map { "\($0) " } ?? "").foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("Pump")) {
                    Button("Add Medtronic") { viewModel.addPump(.minimed) }
                    Button("Add Omnipod") { viewModel.addPump(.omnipod) }
                }
            }
            .toolbar { ToolbarItem(placement: .principal) { Text("Pump Config") } }
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
            .navigationBarTitleDisplayMode(.inline)
            .popover(isPresented: $viewModel.setupPump) {
                PumpSetupView(
                    pumpType: viewModel.setupPumpType,
                    deviceProvider: viewModel.provider.deviceProvider,
                    completionDelegate: viewModel,
                    setupDelegate: nil
                )
            }
        }
    }
}
