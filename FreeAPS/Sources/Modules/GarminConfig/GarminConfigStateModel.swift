import ConnectIQ
import SwiftUI

extension GarminConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!
        @Published var devices: [IQDevice] = []

        override func subscribe() {
            devices = garmin.devices
        }

        func selectDevices() {
            garmin.selectDevices()
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.devices, on: self)
                .store(in: &lifetime)
        }
    }
}
