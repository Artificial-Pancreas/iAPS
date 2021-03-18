import Foundation

struct BasalProfileEntry: JSON, Equatable {
    let start: String
    let minutes: Int
    let rate: Decimal
}

protocol BasalProfileObserver {
    func basalProfileDidChange(_ basalProfile: [BasalProfileEntry])
}
