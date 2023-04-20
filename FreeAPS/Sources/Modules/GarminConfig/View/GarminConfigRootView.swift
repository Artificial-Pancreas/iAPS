import SwiftUI
import Swinject

extension GarminConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section {
                    Button("Select devices") {
                        state.selectDevices()
                    }
                }

                if state.devices.isNotEmpty {
                    Section(header: Text("Connected devices")) {
                        List {
                            ForEach(state.devices, id: \.uuid) { device in
                                Text(device.friendlyName)
                            }
                            .onDelete(perform: onDelete)
                        }
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Garmin Watch")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private func onDelete(offsets: IndexSet) {
            state.devices.remove(atOffsets: offsets)
            state.deleteDevice()
        }
    }
}
