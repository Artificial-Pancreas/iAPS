import Foundation

struct Thresholds: Identifiable, Equatable {
    var id: String { UUID().uuidString }
    let glucose: String
    let setting: String
    let threshold: String
}
