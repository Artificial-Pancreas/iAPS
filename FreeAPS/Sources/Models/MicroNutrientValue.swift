import Foundation

struct MicronutrientValue: Identifiable, Equatable, Codable, Hashable {
    let id: UUID
    let substance: MicroNutrient
    var amount: Decimal
    var amountPer100: Decimal

    var unit: String { substance.unit }
    var name: String { substance.displayName }

    var isVitamin: Bool {
        substance.coreDataType == "vitamin"
    }

    init(
        id: UUID = UUID(),
        substance: MicroNutrient,
        amount: Decimal,
        amountPer100: Decimal
    ) {
        self.id = id
        self.substance = substance
        self.amount = amount
        self.amountPer100 = amountPer100
    }

    enum CodingKeys: String, CodingKey {
        case id
        case substance
        case amount
        case amountPer100
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        let rawSubstance = try container.decode(String.self, forKey: .substance)

        guard let substance = MicroNutrient(
            rawValue: rawSubstance.lowercased()
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .substance,
                in: container,
                debugDescription: "Unknown micronutrient: \(rawSubstance)"
            )
        }

        self.substance = substance

        amount = try container.decode(Decimal.self, forKey: .amount)

        amountPer100 = try container.decodeIfPresent(
            Decimal.self,
            forKey: .amountPer100
        ) ?? 0
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

struct SafeMicronutrientValue: Decodable {
    let value: MicronutrientValue?

    init(from decoder: Decoder) throws {
        do {
            value = try MicronutrientValue(from: decoder)
        } catch {
            value = nil
        }
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
