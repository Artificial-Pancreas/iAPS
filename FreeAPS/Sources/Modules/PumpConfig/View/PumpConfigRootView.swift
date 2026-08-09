import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            NavigationView {
                Form {
                    if let pumpManager = state.deviceManager.pumpManager, pumpManager.isOnboarded {
                        Section(header: Text("Model")) {
                            Button {
                                state.setupPump(pumpManager.pluginIdentifier)
                            } label: {
                                HStack {
                                    Image(uiImage: pumpManager.smallImage ?? UIImage())
                                        .resizable()
                                        .scaledToFit()
                                        .padding()
                                        .frame(maxWidth: 100)
                                    Text(pumpManager.localizedTitle)
                                }
                            }
                        }
                        Section {
                            if let status = pumpManager.pumpStatusHighlight?.localizedMessage {
                                HStack {
                                    Text(status.replacingOccurrences(of: "\n", with: " "))
                                }
                            }
                            if state.pumpManagerStatus?.deliveryIsUncertain ?? false {
                                HStack {
                                    Text("Pump delivery uncertain").foregroundColor(.red)
                                }
                            }
                            if state.alertNotAck {
                                Spacer()
                                Button("Acknowledge all alerts") { state.ack() }
                            }
                        }
                    } else if let pumpManager = state.deviceManager.pumpManager {
                        // This corresponds to the "Re-connect pump!" message on the home screen.
                        // Before version 8, iAPS had a bug preventing the Medtronic pump manager from completing the onboarding.
                        // So the pump ended up in a state with `onboarded=false` forever.
                        // The pump kept working correctly, but the state was inconsistent.
                        // In version 8, we introduced a check for this situation instructing the user to re-connect the pump.
                        // But since the pump manager is already initialized (restored from state at app start), and already remembers/holds the RileyLink connection,
                        // that RileyLink device would never show up in the list.
                        // The fix for this is to remove the pump manager completely and restart iAPS to clear the pump manager in-memory state.
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Incomplete pump setup")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text(
                                    "The previous setup for \(pumpManager.localizedTitle) did not finish fully/correctly. Remove it and restart iAPS before adding your pump again (otherwise your RileyLink device may not show up in the device list)."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            }
                            Button(role: .destructive) {
                                state.removePump()
                            } label: {
                                Text("Remove pump")
                            }
                        }
                    } else {
                        Section {
                            ForEach(state.deviceManager.availablePumpManagers, id: \.identifier) { pump in
                                VStack(alignment: .leading) {
                                    Button("Add " + pump.localizedTitle) {
                                        state.setupPump(pump.identifier)
                                    }
                                }
                            }
                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle("Pump config")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $state.pumpSetupPresented) {
                    if let pumpIdentifier = state.pumpIdentifierToSetUp {
                        if let pumpManager = state.deviceManager.pumpManager, pumpManager.isOnboarded {
                            PumpSettingsView(
                                pumpManager: pumpManager,
                                deviceManager: state.deviceManager,
                                completionDelegate: state
                            )
                        } else {
                            PumpSetupView(
                                pumpIdentifier: pumpIdentifier,
                                pumpInitialSettings: state.initialSettings,
                                deviceManager: state.deviceManager,
                                completionDelegate: state
                            )
                        }
                    }
                }
            }
        }
    }
}
