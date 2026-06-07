import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        @Environment(AppUIState.self) private var appUIState

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            NavigationView {
                Form {
                    if let pumpInfo = appUIState.pumpInfo, pumpInfo.isOnboarded {
                        Section(header: Text("Model")) {
                            Button {
                                state.showCurrentPumpSettings()
                            } label: {
                                HStack {
                                    Image(uiImage: pumpInfo.image ?? UIImage())
                                        .resizable()
                                        .scaledToFit()
                                        .padding()
                                        .frame(maxWidth: 100)
                                    Text(pumpInfo.name)
                                }
                            }
                        }
                        Section {
                            if let status = appUIState.pumpStatus?.statusHighlight {
                                HStack {
                                    Text(status.replacingOccurrences(of: "\n", with: " "))
                                }
                            }
                            if appUIState.pumpStatus?.deliveryIsUncertain ?? false {
                                HStack {
                                    Text("Pump delivery uncertain").foregroundColor(.red)
                                }
                            }
                            if appUIState.alertNotAck {
                                Spacer()
                                Button("Acknowledge all alerts") { state.ack() }
                            }
                        }
                    } else {
                        Section {
                            ForEach(state.deviceManager.availablePumpManagers, id: \.identifier) { pump in
                                VStack(alignment: .leading) {
                                    Button("Add " + pump.localizedTitle) {
                                        state.setupNewPump(pump.identifier)
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
                        PumpSetupView(
                            pumpIdentifier: pumpIdentifier,
                            pumpInitialSettings: state.initialSettings,
                            deviceManager: state.deviceManager,
                            completionDelegate: state
                        )
                    }
                }
                .sheet(isPresented: $state.pumpSettingsPresented) {
                    PumpSettingsView(
                        deviceManager: state.deviceManager,
                        completionDelegate: state
                    )
                }
            }
        }
    }
}
