import Combine
import Foundation

enum BasalProfileEditor {
    enum Config {}

    class Item: Identifiable, Hashable, Equatable {
        let id = UUID()
        var rateIndex = 0
        var timeIndex = 0

        init(rateIndex: Int, timeIndex: Int) {
            self.rateIndex = rateIndex
            self.timeIndex = timeIndex
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.timeIndex == rhs.timeIndex
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(timeIndex)
        }
    }
}

protocol BasalProfileEditorProvider: Provider {
    var profile: [BasalProfileEntry] { get }
    var supportedBasalRates: [Decimal]? { get }
    func saveProfile(_ profile: [BasalProfileEntry]) -> AnyPublisher<Void, Error>
}
