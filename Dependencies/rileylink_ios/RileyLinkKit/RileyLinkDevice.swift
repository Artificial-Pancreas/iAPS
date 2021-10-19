//
//  RileyLinkDevice.swift
//  RileyLinkKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import RileyLinkBLEKit


extension RileyLinkDevice.Status {
    public var firmwareDescription: String {
        let versions = [radioFirmwareVersion, bleFirmwareVersion].compactMap { (version: CustomStringConvertible?) -> String? in
            if let version = version {
                return String(describing: version)
            } else {
                return nil
            }
        }

        return versions.joined(separator: " / ")
    }
}


extension Notification.Name {
    public static let DeviceRadioConfigDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkKit.DeviceRadioConfigDidChange")

    public static let DeviceStateDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkKit.DeviceStateDidChange")
}
