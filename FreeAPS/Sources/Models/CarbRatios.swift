import Foundation

struct CarbRatios: JSON {
    let units: CarbUnit
    let schedule: [CarbRatioEntry]
}

struct CarbRatioEntry: JSON {
    let start: String
    let offset: Int
    let ratio: Decimal
}

enum CarbUnit: String, JSON {
    case grams
    case exchanges
}
