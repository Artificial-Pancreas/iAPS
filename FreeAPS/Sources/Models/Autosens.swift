import Foundation

struct Autosens: JSON {
    let ratio: Decimal
    let newISF: Decimal?
    var timestamp: Date?
}
