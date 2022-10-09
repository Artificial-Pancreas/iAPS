//
//  MockRileyLinkDevice.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import Foundation
import RileyLinkBLEKit
import CoreBluetooth

class MockRileyLinkDevice: RileyLinkDevice {
    var isConnected: Bool = true

    var rlFirmwareDescription: String = "Mock"

    var hasOrangeLinkService: Bool = false

    var hardwareType: RileyLinkHardwareType? = .riley

    var rssi: Int? = nil

    var name: String? = "Mock"

    var deviceURI: String =  "rileylink://Mock"

    var peripheralIdentifier: UUID = UUID()

    var peripheralState: CBPeripheralState = .connected

    func readRSSI() {}

    func setCustomName(_ name: String) {}

    func updateBatteryLevel() {}

    func orangeAction(_ command: OrangeLinkCommand) {}

    func setOrangeConfig(_ config: OrangeLinkConfigurationSetting, isOn: Bool) {}

    func orangeWritePwd() {}

    func orangeClose() {}

    func orangeReadSet() {}

    func orangeReadVDC() {}

    func findDevice() {}

    func setDiagnosticeLEDModeForBLEChip(_ mode: RileyLinkLEDMode) {}

    func readDiagnosticLEDModeForBLEChip(completion: @escaping (RileyLinkLEDMode?) -> Void) {}

    func assertOnSessionQueue() {}

    func sessionQueueAsyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) {}

    func runSession(withName name: String, _ block: @escaping (CommandSession) -> Void) {
        assertionFailure("MockRileyLinkDevice.runSession should not be called during testing.  Use MockPumpOps for communication stubs.")
    }

    func getStatus(_ completion: @escaping (RileyLinkDeviceStatus) -> Void) {
        completion(RileyLinkDeviceStatus(
            lastIdle: Date(),
            name: name,
            version: rlFirmwareDescription,
            ledOn: false,
            vibrationOn: false,
            voltage: 3.0,
            battery: nil,
            hasPiezo: false))
    }
}
