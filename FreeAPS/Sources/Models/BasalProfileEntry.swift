import Foundation

struct BasalProfileEntry: JSON {
    let i: Int
    let start: String
    let minutes: Int
    let rate: Decimal
}
