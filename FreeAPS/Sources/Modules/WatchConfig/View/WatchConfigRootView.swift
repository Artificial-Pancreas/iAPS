import SwiftUI
import Swinject

extension WatchConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section(header: Text("Apple Watch")) {
                    Picker(
                        selection: $state.selectedAwConfig,
                        label: Text("Display on Watch")
                    ) {
                        ForEach(AwConfig.allCases) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                }

                Toggle("Display Protein & Fat", isOn: $state.displayFatAndProteinOnWatch)

                Toggle("Confirm Bolus Faster", isOn: $state.confirmBolusFaster)

                Section {
                    Toggle("Profile Overrides Button / Temp Targets Button", isOn: $state.profilesOrTempTargets)
                } header: { Text("Display either Overides or Temp Targets") }

                Section(header: Text("Garmin Watch")) {
                    List {
                        ForEach(state.devices, id: \.uuid) { device in
                            Text(device.friendlyName)
                        }
                        .onDelete(perform: onDelete)
                    }
                    Button("Add devices") {
                        state.selectGarminDevices()
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Watch Configuration")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private func onDelete(offsets: IndexSet) {
            state.devices.remove(atOffsets: offsets)
            state.deleteGarminDevice()
        }
    }
}
