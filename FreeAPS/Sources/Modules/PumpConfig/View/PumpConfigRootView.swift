import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        private var isPumpSetupPresented: Binding<Bool> {
            Binding<Bool>(
                get: { state.pumpIdentifierToSetUp != nil },
                set: { if !$0 { state.pumpIdentifierToSetUp = nil } }
            )
        }

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("Model")) {
                        if let pumpManager = state.deviceManager.pumpManager {
//                            TODO: [loopkit] fix this
//                            if state.alertNotAck {
//                                Spacer()
//                                Button("Acknowledge all alerts") { state.ack() }
//                            }

                            Button {
                                state.pumpIdentifierToSetUp = pumpManager.pluginIdentifier
                            } label: {
                                HStack {
                                    Image(uiImage: pumpManager.smallImage ?? UIImage()).padding()
                                    Text(pumpManager.localizedTitle)
                                }
                                if let status = pumpManager.pumpStatusHighlight?.localizedMessage {
                                    HStack {
                                        Text(status.replacingOccurrences(of: "\n", with: " ")).font(.caption)
                                    }
                                }
                            }

                        } else {
                            ForEach(state.deviceManager.availablePumpManagers, id: \.identifier) { cgm in
                                VStack(alignment: .leading) {
                                    Button("Add " + cgm.localizedTitle) {
                                        state.pumpIdentifierToSetUp = cgm.identifier
                                    }
                                }
                            }
                        }

//                        if let pumpState = state.pumpState {
//                            Button {
//                                state.setupPump = true
//                            } label: {
//                                HStack {
//                                    Image(uiImage: pumpState.image ?? UIImage()).padding()
//                                    Text(pumpState.name)
//                                }
//                            }
//                            if state.alertNotAck {
//                                Spacer()
//                                Button("Acknowledge all alerts") { state.ack() }
//                            }
//                        } else {
//                            Button("Add Medtronic") { state.addPump(.minimed) }
//                            Button("Add Omnipod") { state.addPump(.omnipod) }
//                            Button("Add Omnipod Dash") { state.addPump(.omnipodBLE) }
//                            Button("Add Dana-i/RS") { state.addPump(.dana) }
//                            Button("Add Simulator") { state.addPump(.simulator) }
//                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle("Pump config")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: isPumpSetupPresented) {
                    if let pumpIdentifier = state.pumpIdentifierToSetUp {
                        if let pumpManager = state.deviceManager.pumpManager {
                            PumpSettingsView(
                                pumpManager: pumpManager,
                                bluetoothManager: state.provider.apsManager.bluetoothManager!,
                                completionDelegate: state,
                                onboardingDelegate: state.deviceManager.pumpManagerOnboardingDelegate
                            )
                        } else {
                            PumpSetupView(
                                pumpIdentifier: pumpIdentifier,
                                pumpInitialSettings: state.initialSettings,
                                deviceManager: state.deviceManager,
                                bluetoothManager: state.provider.apsManager.bluetoothManager!,
                                completionDelegate: state,
                                onboardingDelegate: state.deviceManager.pumpManagerOnboardingDelegate
                            )
                        }
                    }
                }
            }
        }
    }
}
