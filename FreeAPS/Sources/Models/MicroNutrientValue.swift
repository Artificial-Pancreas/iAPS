import Foundation

struct MicronutrientValue: Identifiable, Equatable {
    let id = UUID()
    let substance: MicroNutrient
    let amount: Decimal
    let amountPer100: Decimal

    var unit: String { substance.unit }
    var name: String { substance.displayName }

    var isVitamin: Bool {
        substance.coreDataType == "vitamin"
    }
}

extension MicronutrientValue {
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0

        let number = NSDecimalNumber(decimal: amount)

        let formatted = formatter.string(from: number) ?? "\(number)"
        return "\(formatted) \(unit)"
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
