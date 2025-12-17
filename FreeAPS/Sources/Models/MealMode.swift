import Foundation

class MealMode: ObservableObject {
    enum Mode {
        case image
        case barcode
        case presets
        case search
        case meal
    }

    var mode: Mode = .meal
}
