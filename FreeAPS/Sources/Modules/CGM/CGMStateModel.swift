import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() var appCoordinator: AppCoordinator!

        @Published var cgmSetupPresented: Bool = false
        @Published var cgmSettingsPresented: Bool = false
        @Published private(set) var cgmIdentifierToSetUp: String? = nil

        @Published var smoothGlucose = false
        @Published var sensorDays: Double = 10

        @Published var cgmInfo: CgmDisplayInfo?
        @Published var cgmStatus: CgmDisplayStatus?

        override func subscribe() async {
            subscribeSetting(\.smoothGlucose, on: $smoothGlucose) { self.smoothGlucose = $0 }
            subscribeSetting(\.sensorDays, on: $sensorDays) { self.sensorDays = $0 }

            appCoordinator.cgmInfo
                .receive(on: DispatchQueue.main)
                .assign(to: &$cgmInfo)

            appCoordinator.cgmStatus
                .receive(on: DispatchQueue.main)
                .assign(to: &$cgmStatus)
        }

        func removePumpAsCGM() {
            deviceManager.removePumpAsCGM()
        }

        func setupNewCgm(_ identifier: String?) {
            Task {
                self.cgmIdentifierToSetUp = identifier
                self.cgmSetupPresented = true
                self.cgmSettingsPresented = false
            }
        }

        func showCurrentCgmSettings() {
            guard let cgmInfo else { return }
            let currentCgmIdentifier = cgmInfo.identifier
            let isOnboarded = cgmInfo.isOnboarded

            Task {
                self.cgmIdentifierToSetUp = currentCgmIdentifier
                self.cgmSetupPresented = isOnboarded == false
                self.cgmSettingsPresented = isOnboarded == true
            }
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        if cgmSetupPresented {
            // setup finished -> keep the expected setup→settings progression
            cgmSetupPresented = false
            if cgmInfo?.isOnboarded == true {
                // present settings after setup
                DispatchQueue.main.async { self.cgmSettingsPresented = true }
            }
        } else if cgmSettingsPresented {
            // settings finished -> close
            cgmSettingsPresented = false
        }
    }
}
