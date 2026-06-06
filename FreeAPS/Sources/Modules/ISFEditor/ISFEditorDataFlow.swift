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
    var isfSchedule: InsulinSensitivities { get async }
    func saveProfile(_ profile: InsulinSensitivities) async
    var autosense: Autosens { get async }
    var autotune: Autotune? { get async }
}
