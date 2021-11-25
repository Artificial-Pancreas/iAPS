import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section(header: Text("Model")) {
                    if let pumpState = state.pumpState {
                        Button {
                            state.setupPump = true
                        } label: {
                            HStack {
                                Image(uiImage: pumpState.image ?? UIImage()).padding()
                                Text(pumpState.name)
                            }
                        }
                    } else {
                        Button("Add Medtronic") { state.addPump(.minimed) }
                        Button("Add Omnipod") { state.addPump(.omnipod) }
                        Button("Add Simulator") { state.addPump(.simulator) }
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Pump config")
            .navigationBarTitleDisplayMode(.automatic)
            .sheet(isPresented: $state.setupPump) {
                if let pumpManager = state.provider.apsManager.pumpManager {
                    PumpSettingsView(pumpManager: pumpManager, completionDelegate: state)
                } else {
                    PumpSetupView(
                        pumpType: state.setupPumpType,
                        pumpInitialSettings: state.initialSettings,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
        }
    }
}
