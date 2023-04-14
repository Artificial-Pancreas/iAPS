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
                        ForEach(state.devices, id: \.uuid) { device in
                            Text(device.friendlyName)
                        }
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Garmin Watch")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
