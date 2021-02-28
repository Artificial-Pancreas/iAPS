import Foundation

struct BloodGlucose: JSON {
    enum Direction: String, JSON {
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
    let date: Date
    let filtered: Double?
    let noise: Int?

    var glucose: Int { sgv ?? 0 }

    var isStateValid: Bool { glucose >= 39 && noise ?? 1 != 4 }
}
