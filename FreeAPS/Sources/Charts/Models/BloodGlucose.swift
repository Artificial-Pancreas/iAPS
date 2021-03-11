//
//  BloodGlucose.swift
//  free-aps-charts-final
//
//  Created by Яков Карпов on 12.03.2021.
//

import Foundation

struct BloodGlucose {
    enum Direction: String {
        case tripleUp = "TripleUp"
        case doubleUp = "DoubleUp"
        case singleUp = "SingleUp"
        case fortyFiveUp = "FortyFiveUp"
        case flat = "Flat"
        case fortyFiveDown = "FortyFiveDown"
        case singleDown = "SingleDown"
        case doubleDown = "DoubleDown"
        case tripleDown = "TripleDown"
        case none = "NONE"
        case notComputable = "NOT COMPUTABLE"
        case rateOutOfRange = "RATE OUT OF RANGE"
    }

    var sgv: Int?
    let direction: Direction?
    let date: UInt64
    let dateString: Date
    let filtered: Double?
    let noise: Int?

    var glucose: Int?

    var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }
}
