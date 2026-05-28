import Foundation

struct TemporaryData: JSON, Equatable {
    var forBolusView = CarbsEntry(
        id: "",
        createdAt: .distantPast,
        actualDate: .distantPast,
        carbs: 0,
        fat: 0,
        protein: 0,
        fiber: nil,
        note: "",
        enteredBy: "",
        isFPU: false,
        micronutrient: nil
    )
}
