import Foundation

class MealMode: ObservableObject {
    enum Mode {
        case image
        case barcode
        case presets
        case meal
        case voice
    }

    var mode: Mode = .meal
}
