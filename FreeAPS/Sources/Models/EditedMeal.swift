import Foundation

struct EditableMeal {
    var carbs: Decimal = 0
    var fat: Decimal = 0
    var protein: Decimal = 0
    var fiber: Decimal = 0
    var note: String = ""
    var micronutrient: [MicronutrientValue] = []
}
