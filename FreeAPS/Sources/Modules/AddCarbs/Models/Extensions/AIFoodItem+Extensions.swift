import Foundation

extension AIFoodItem {
    func toCarbsEntry(servingSize: Decimal = 100.0) -> CarbsEntry {
        let scalingFactor = servingSize / 100.0

        return CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: carbs * scalingFactor,
            fat: fat * scalingFactor,
            protein: protein * scalingFactor,
            note: "\(name)\(brand != nil ? " (\(brand!))" : "") - AI detected",
            enteredBy: CarbsEntry.manual,
            isFPU: false
        )
    }
}
