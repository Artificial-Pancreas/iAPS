//
//  NSUserDefaults.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 11/24/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension UserDefaults {
    var passiveModeEnabled: Bool {
        get {
            return bool(forKey: "passiveModeEnabled")
        }
        set {
            set(newValue, forKey: "passiveModeEnabled")
        }
    }

    var stayConnected: Bool {
        get {
            return object(forKey: "stayConnected") != nil ? bool(forKey: "stayConnected") : true
        }
        set {
            set(newValue, forKey: "stayConnected")
        }
    }

    var transmitterID: String {
        get {
            return string(forKey: "transmitterID") ?? "500000"
        }
        set {
            set(newValue, forKey: "transmitterID")
        }
    }
}
