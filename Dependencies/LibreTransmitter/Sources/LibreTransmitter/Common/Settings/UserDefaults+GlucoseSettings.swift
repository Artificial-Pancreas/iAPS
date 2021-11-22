//
//  Userdefaults+Alarmsettings.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 20/04/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation
import HealthKit

extension UserDefaults {
    private enum Key: String {
        case mmBackfillFromHistory = "no.bjorninge.mmBackfillFromHistory"
        case mmBackfillFromTrend = "no.bjorninge.mmBackfillFromTrend"
    }

    var mmBackfillFromHistory: Bool {
        get {
             optionalBool(forKey: Key.mmBackfillFromHistory.rawValue) ?? true
        }
        set {
            set(newValue, forKey: Key.mmBackfillFromHistory.rawValue)
        }
    }

    var mmBackfillFromTrend: Bool {
        get {
            optionalBool(forKey: Key.mmBackfillFromTrend.rawValue) ?? false
        }
        set {
            set(newValue, forKey: Key.mmBackfillFromTrend.rawValue)
        }
    }
}
