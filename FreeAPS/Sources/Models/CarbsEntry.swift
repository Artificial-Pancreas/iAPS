import Foundation

struct CarbsEntry: JSON, Equatable, Hashable {
    let id: String?
    var createdAt: Date
    let actualDate: Date?
    var carbs: Decimal
    let fat: Decimal?
    let protein: Decimal?
    let fiber: Decimal?
    let note: String?
    let enteredBy: String?
    let isFPU: Bool?

    var micronutrient: [MicronutrientValue]?

    /// A downloaded Nightscout treatment only: its `id` field, the local id iAPS uploaded it with (never stored)
    var uploadedID: String? = nil

    static let manual = "iAPS"
    static let watch = "iAPS Watch"
    static let remote = "Nightscout operator"
    static let appleHealth = "applehealth"
    static let shortcut = "iAPS shortcut"

    static func == (lhs: CarbsEntry, rhs: CarbsEntry) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }

    private static let localSources: Set<String> = [manual, watch, remote, shortcut]
}

extension CarbsEntry {
    var isEmpty: Bool {
        carbs == 0 && fat == 0 && protein == 0 &&
            fiber == 0 && micronutrient?.allSatisfy { $0.amount == 0 } ?? true
    }

    var isLocallyEntered: Bool {
        guard let enteredBy else { return false }
        return Self.localSources.contains(enteredBy)
    }

    var isSyncableMeal: Bool {
        isFPU != true
            && isLocallyEntered
            && (carbs > 0 || (fat ?? 0) > 0 || (protein ?? 0) > 0)
    }
}

extension CarbsEntry {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt = "created_at"
        case actualDate
        case carbs
        case fat
        case protein
        case fiber
        case note
        case enteredBy
        case isFPU
        case micronutrient
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        actualDate = try container.decodeIfPresent(Date.self, forKey: .actualDate)
        carbs = try container.decode(Decimal.self, forKey: .carbs)
        // lenient: Nightscout's careportal stores fat and protein as the form's strings
        fat = Self.lenientDecimal(container, .fat)
        protein = Self.lenientDecimal(container, .protein)
        fiber = Self.lenientDecimal(container, .fiber)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        enteredBy = try container.decodeIfPresent(String.self, forKey: .enteredBy)
        isFPU = try container.decodeIfPresent(Bool.self, forKey: .isFPU)

        let wrapped = try container.decodeIfPresent(
            [SafeMicronutrientValue].self,
            forKey: .micronutrient
        ) ?? []

        micronutrient = wrapped.compactMap(\.value)

        let nightscout = try decoder.container(keyedBy: NightscoutKeys.self)
        uploadedID = try? nightscout.decodeIfPresent(String.self, forKey: .uploadedID)
    }

    private enum NightscoutKeys: String, CodingKey {
        case uploadedID = "id"
    }

    /// A number, or a string of one; anything else (or nothing) is nil
    private static func lenientDecimal(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Decimal? {
        if let value = try? container.decodeIfPresent(Decimal.self, forKey: key) {
            return value
        }
        guard let string = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let number = Double(trimmed), number.isFinite else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// A downloaded carbs entry that fails to decode is left out, not the whole download
struct LossyCarbsEntry: Decodable, Sendable {
    let entry: CarbsEntry?

    init(from decoder: Decoder) throws {
        entry = try? CarbsEntry(from: decoder)
    }
}
