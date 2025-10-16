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
