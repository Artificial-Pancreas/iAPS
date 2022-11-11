//
//  MockRileyLinkProvider.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import Foundation
import RileyLinkBLEKit

class MockRileyLinkProvider: RileyLinkDeviceProvider {

    init(devices: [RileyLinkDevice]) {
        self.devices = devices
    }

    var devices: [RileyLinkDevice]

    var delegate: RileyLinkDeviceProviderDelegate?

    var idleListeningState: RileyLinkBluetoothDevice.IdleListeningState = .disabled

    var idleListeningEnabled: Bool = false

    var timerTickEnabled: Bool = false

    var connectingCount: Int = 0

    func deprioritize(_ device: RileyLinkDevice, completion: (() -> Void)?) {
    }

    func assertIdleListening(forcingRestart: Bool) {
    }

    func getDevices(_ completion: @escaping ([RileyLinkDevice]) -> Void) {
        completion(devices)
    }

    func connect(_ device: RileyLinkDevice) {
    }

    func disconnect(_ device: RileyLinkDevice) {
    }

    func setScanningEnabled(_ enabled: Bool) {
    }

    func shouldConnect(to deviceID: String) -> Bool {
        return false
    }

    var debugDescription: String = "MockRileyLinkProvider"

}
