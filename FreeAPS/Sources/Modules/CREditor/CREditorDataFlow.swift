import Foundation

enum CREditor {
    enum Config {}

    class Item: Identifiable, Hashable, Equatable {
        let id = UUID()
        var rateIndex = 0
        var timeIndex = 0

        init(rateIndex: Int, selectedIndex: Int) {
            self.rateIndex = rateIndex
            timeIndex = selectedIndex
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.timeIndex == rhs.timeIndex
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(timeIndex)
        }
    }
}

protocol CREditorProvider: Provider {
    var profile: CarbRatios { get }
    func saveProfile(_ profile: CarbRatios)
}
