import Foundation

struct FoodAnalysisResult: Identifiable, Equatable {
    let id = UUID()
    let imageType: ImageAnalysisType?
    let foodItemsDetailed: [AnalysedFoodItem]
    let briefDescription: String?
    let overallDescription: String?
    let diabetesConsiderations: String?
    let source: FoodItemSource?
    var barcode: String? = nil
    var textQuery: String? = nil

    static func == (lhs: FoodAnalysisResult, rhs: FoodAnalysisResult) -> Bool {
        lhs.id == rhs.id
    }

    // Helper function to clean food names for display
    private func cleanFoodName(_ name: String) -> String {
        var cleaned = name

        // Remove common technical terms while preserving essential info
        let removals = [
            " Breast", " Fillet", " Thigh", " Florets", " Spears",
            " Cubes", " Medley", " Portion"
        ]

        for removal in removals {
            cleaned = cleaned.replacingOccurrences(of: removal, with: "")
        }

        // Capitalize first letter and trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? name : cleaned
    }

    var totalCalories: Decimal {
        foodItemsDetailed.compactMap(\.caloriesInThisPortion).reduce(0, +)
    }

    var totalCarbs: Decimal {
        foodItemsDetailed.compactMap(\.carbsInThisPortion).reduce(0, +)
    }

    var totalFat: Decimal {
        foodItemsDetailed.compactMap(\.fatInThisPortion).reduce(0, +)
    }

    var totalProtein: Decimal {
        foodItemsDetailed.compactMap(\.proteinInThisPortion).reduce(0, +)
    }
}

extension FoodAnalysisResult: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let imageType: ImageAnalysisType? = try container
            .decodeIfPresent(ImageAnalysisType.self, forKey: .imageType) ?? .foodPhoto

        let foodItemsDetailed: [AnalysedFoodItem] = try container.decode([AnalysedFoodItem].self, forKey: .foodItemsDetailed)

        let briefDescription: String? = try container.decodeTrimmedIfPresent(forKey: .briefDescription)
        let overallDescription: String? = try container.decodeTrimmedIfPresent(forKey: .overallDescription)

        let diabetesConsiderations: String? = try container.decodeTrimmedIfPresent(forKey: .diabetesConsiderations)

        self.imageType = imageType
        self.foodItemsDetailed = foodItemsDetailed
        self.briefDescription = briefDescription
        self.overallDescription = overallDescription
        self.diabetesConsiderations = diabetesConsiderations
        source = imageType == .textSearch ? .aiText : .ai
    }

    private enum CodingKeys: String, CodingKey {
        case imageType = "image_type"
        case foodItemsDetailed = "food_items"
        case briefDescription = "brief_description"
        case overallDescription = "overall_description"
        case diabetesConsiderations = "diabetes_considerations"
    }
}

/// Confidence level for AI analysis
enum AIConfidenceLevel: String, JSON, Identifiable, CaseIterable {
    case high
    case medium
    case low

    var id: AIConfidenceLevel { self }
}

extension AIConfidenceLevel {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode numeric confidence first
        if let numeric = try? container.decode(Double.self) {
            if numeric >= 0.8 {
                self = .high
            } else if numeric >= 0.5 {
                self = .medium
            } else {
                self = .low
            }
            return
        }

        // Fallback to string-based confidence values
        if let stringValue = try? container.decode(String.self) {
            switch stringValue.lowercased() {
            case "high":
                self = .high
            case "medium":
                self = .medium
            case "low":
                self = .low
            default:
                // Attempt to parse numeric from string
                if let numericFromString = Double(stringValue) {
                    if numericFromString >= 0.8 {
                        self = .high
                    } else if numericFromString >= 0.5 {
                        self = .medium
                    } else {
                        self = .low
                    }
                } else {
                    self = .medium // Default confidence
                }
            }
            return
        }

        // Default if neither numeric nor string could be decoded
        self = .medium
    }
}

/// Type of image being analyzed
enum ImageAnalysisType: String, JSON, Identifiable, CaseIterable {
    case foodPhoto = "food_photo"
    case menuItem = "menu_item"
    case recipePhoto = "recipe_photo"
    case textSearch = "text_search"

    var id: ImageAnalysisType { self }
}

extension KeyedDecodingContainer {
    func decodeTrimmedNonEmpty(forKey key: Key) throws -> String {
        let raw = try decode(String.self, forKey: key)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected non-empty string after trimming."
            )
        }
        return trimmed
    }

    func decodeTrimmedIfPresent(forKey key: Key) throws -> String? {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func decodeNumber(forKey key: Key, ensuringNonNegative: Bool = true) throws -> Decimal {
        // Try Double directly
        if let double = try? decode(Decimal.self, forKey: key) {
            return ensuringNonNegative ? max(0, double) : double
        }
        // Try Int and convert
        if let intVal = try? decode(Int.self, forKey: key) {
            let converted = Decimal(intVal)
            return ensuringNonNegative ? max(0, converted) : converted
        }
        // Try String and convert
        if let stringVal = try? decode(String.self, forKey: key) {
            let trimmed = stringVal.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Decimal(from: trimmed) {
                return ensuringNonNegative ? max(0, parsed) : parsed
            }
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "String value for key \(key.stringValue) is not a valid Double: \(stringVal)"
            )
        }
        // If value is explicitly null or not present, surface a missing value error
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "No convertible numeric value found for key \(key.stringValue)"
            )
        )
    }

    /// Decode a numeric value if present. Accepts Double, Int, or String representations.
    /// Optionally clamps negatives to 0.
    func decodeNumberIfPresent(forKey key: Key, ensuringNonNegative: Bool = true) throws -> Decimal? {
        // If the key is not present at all, return nil early
        if contains(key) == false { return nil }

        if let double = try? decode(Decimal.self, forKey: key) {
            return ensuringNonNegative ? max(0, double) : double
        }
        if let intVal = try? decode(Int.self, forKey: key) {
            let converted = Decimal(intVal)
            return ensuringNonNegative ? max(0, converted) : converted
        }
        if let stringVal = try? decode(String.self, forKey: key) {
            let trimmed = stringVal.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Decimal(from: trimmed) {
                return ensuringNonNegative ? max(0, parsed) : parsed
            }
            return nil
        }
        return nil
    }
}

extension FoodAnalysisResult {
    private static var fields: [(FoodAnalysisResult.CodingKeys, Any)] {
        [
            (.briefDescription, "generate a SHORT UI TITLE describing the analyzed food; (language)"),
            (.diabetesConsiderations, "carb sources, GI impact (low/medium/high), timing considerations; (language)")
        ]
    }

    static var schemaVisual: [(String, Any)] {
        let fields = [
            (.imageType, "string enum: food_photo or menu_item or recipe_photo"),
            (.foodItemsDetailed, AnalysedFoodItem.schemaVisual),
            (.overallDescription, "describe what you see on the photo; (language)")
        ] + self.fields

        return fields.map { key, value in
            (key.rawValue, value)
        }
    }

    static var schemaText: [(String, Any)] {
        let fields = [
            (.imageType, "string, always set to: text_search"),
            (.foodItemsDetailed, [AnalysedFoodItem.schemaText]),
            (.overallDescription, "describe what you perceived from the user input; (language)")
        ] + self.fields

        return fields.map { key, value in
            (key.rawValue, value)
        }
    }
}
