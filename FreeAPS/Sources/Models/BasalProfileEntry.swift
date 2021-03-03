import Foundation

struct BasalProfileEntry: JSON {
    let start: String
    let minutes: Int
    let rate: Decimal
}
