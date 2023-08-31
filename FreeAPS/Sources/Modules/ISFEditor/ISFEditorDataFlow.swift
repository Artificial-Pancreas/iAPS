import Foundation

enum ISFEditor {
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

protocol ISFEditorProvider: Provider {
    var profile: InsulinSensitivities { get }
    func saveProfile(_ profile: InsulinSensitivities)
    var autosense: Autosens { get }
    var autotune: Autotune? { get }
    var suggestion: Suggestion? { get }
}
