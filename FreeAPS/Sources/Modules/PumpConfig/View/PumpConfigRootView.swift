import SwiftUI
import Swinject

struct SmoothiOSButtonStyle: ButtonStyle {
    var backgroundColor: Color

    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .padding()
            .foregroundColor(Color.white)
            .background(backgroundColor)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Animation.easeOut(duration: 0.15), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

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

                        if pumpManager.pluginIdentifier == "Dana" {
                            Section(
                                header: Text("Site & Reservoir"),
                                footer: Text(
                                    "The old entry will be automatically deleted before the new date is securely synchronized with Nightscout."
                                )
                            ) {
                                DatePicker(
                                    "Changed At",
                                    selection: $state.changedAt,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .padding(.vertical, 4)

                                // SEXY SMOOTH BUTTON 1: Site Change
                                Button(action: {
                                    state.confirmation = .siteChange
                                }) {
                                    HStack {
                                        Image(systemName: "drop.fill")
                                            .font(.title3)
                                        Text("Log Site Change")
                                            .fontWeight(.semibold)
                                            .font(.body)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(SmoothiOSButtonStyle(backgroundColor: .blue))
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)

                                // SEXY SMOOTH BUTTON 2: Reservoir Change
                                Button(action: {
                                    state.confirmation = .reservoirChange
                                }) {
                                    HStack {
                                        Image(systemName: "syringe.fill")
                                            .font(.title3)
                                        Text("Log Reservoir Change")
                                            .fontWeight(.semibold)
                                            .font(.body)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(SmoothiOSButtonStyle(backgroundColor: .orange))
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }

                    } else {
                        Section {
                            ForEach(state.deviceManager.availablePumpManagers, id: \.identifier) { pump in
                                VStack(alignment: .leading) {
                                    Button("Add " + pump.localizedTitle) {
                                        state.setupPump(pump.identifier)
                                    }
                                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                }
                            }
                        }
                    }
                }
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
                .alert(item: $state.confirmation) { confirmationType in
                    switch confirmationType {
                    case .siteChange:
                        return Alert(
                            title: Text("Log Site Change?"),
                            message: Text(
                                "Do you want to set the Site Change to\n\(state.formattedChangedAt)?\n\nThe old entry will be automatically deleted from Nightscout."
                            ),
                            primaryButton: .default(Text("Save"), action: { state.logSiteChange() }),
                            secondaryButton: .cancel(Text("Cancel"))
                        )
                    case .reservoirChange:
                        return Alert(
                            title: Text("Log Reservoir Change?"),
                            message: Text(
                                "Do you want to set the Reservoir Change to\n\(state.formattedChangedAt)?\n\nThe old entry will be automatically deleted from Nightscout."
                            ),
                            primaryButton: .default(Text("Save"), action: { state.logReservoirChange() }),
                            secondaryButton: .cancel(Text("Cancel"))
                        )
                    }
                }
            }
        }
    }
}
