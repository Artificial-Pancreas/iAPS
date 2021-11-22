//
//  UserDefaults+Bluetooth.swift
//  MiaomiaoClientUI
//
//  Created by Bjørn Inge Berg on 27/07/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation
//import MiaomiaoClient

extension UserDefaults {
    private enum Key: String {
        case bluetoothDeviceUUIDString = "no.bjorninge.bluetoothDeviceUUIDString"
        case libre2UiD = "no.bjorninge.libre2uid"
    }

    public var preSelectedUid: Data? {
        get {
            return data(forKey: Key.libre2UiD.rawValue)

        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Key.libre2UiD.rawValue)
            } else {
                print("Removing preSelectedUid")
                removeObject(forKey: Key.libre2UiD.rawValue)
            }
        }
    }

    public var preSelectedDevice: String? {
        get {
            if let astr = string(forKey: Key.bluetoothDeviceUUIDString.rawValue) {
                return astr.count > 0 ? astr : nil
            }
            return nil
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Key.bluetoothDeviceUUIDString.rawValue)
            } else {
                removeObject(forKey: Key.bluetoothDeviceUUIDString.rawValue)
            }
        }
    }
}
