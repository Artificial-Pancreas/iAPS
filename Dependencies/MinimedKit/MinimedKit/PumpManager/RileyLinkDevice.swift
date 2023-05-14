//
//  RileyLinkDevice.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import HealthKit
import RileyLinkBLEKit


extension RileyLinkDeviceStatus {
    func device(pumpID: String, pumpModel: PumpModel) -> HKDevice {
        return HKDevice(
            name: name,
            manufacturer: "Medtronic",
            model: pumpModel.rawValue,
            hardwareVersion: nil,
            firmwareVersion: version,
            softwareVersion: String(MinimedKitVersionNumber),
            localIdentifier: pumpID,
            udiDeviceIdentifier: nil
        )
    }
}
