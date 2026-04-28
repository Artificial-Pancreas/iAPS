import Foundation

struct OpenFoodFactsSearchResponse: Codable {
    let products: [OpenFoodFactsProduct]
    let count: Int
    let page: Int
    let pageCount: Int
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case products
        case count
        case page
        case pageCount = "page_count"
        case pageSize = "page_size"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        products = try container.decode([OpenFoodFactsProduct].self, forKey: .products)
        count = try Self.decodeFlexibleInt(from: container, forKey: .count)
        page = try Self.decodeFlexibleInt(from: container, forKey: .page)
        pageCount = try Self.decodeFlexibleInt(from: container, forKey: .pageCount)
        pageSize = try Self.decodeFlexibleInt(from: container, forKey: .pageSize)
    }

    /// Decode an Int that might come as a String or Int from the API
    private static func decodeFlexibleInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int {
        // Try as Int first
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }
        // Try as String and convert
        if let stringValue = try? container.decode(String.self, forKey: key),
           let intValue = Int(stringValue)
        {
            return intValue
        }
        // Throw an error if neither works
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: container.codingPath + [key],
                debugDescription: "Expected Int or String containing Int for key '\(key.stringValue)'"
            )
        )
    }
}

/// Response structure for single product lookup by barcode
struct OpenFoodFactsProductResponse: Codable {
    let code: String
    let product: OpenFoodFactsProduct?
    let status: Int
    let statusVerbose: String

    enum CodingKeys: String, CodingKey {
        case code
        case product
        case status
        case statusVerbose = "status_verbose"
    }
}

// MARK: - Core Product Models

/// Food data source types
enum FoodDataSource: String, CaseIterable, Codable {
    case barcodeScan = "barcode_scan"
    case textSearch = "text_search"
    case aiAnalysis = "ai_analysis"
    case manualEntry = "manual_entry"
    case unknown
}

/// Represents a food product from OpenFoodFacts database
struct OpenFoodFactsProduct: Identifiable, Hashable {
    let id: String
    let productName: String?
    let brands: String?
    let categories: String?
    let nutriments: Nutriments
    let servingSize: String?
    let servingQuantity: Decimal?

    let imageURL: String?
    let imageFrontURL: String?

    let code: String?
    let dataSource: FoodDataSource

    init(
        id: String,
        productName: String?,
        brands: String?,
        categories: String? = nil,
        nutriments: Nutriments,
        servingSize: String?,
        servingQuantity: Decimal?,
        imageURL: String?,
        imageFrontURL: String?,
        code: String?,
        dataSource: FoodDataSource = .unknown
    ) {
        self.id = id
        self.productName = productName
        self.brands = brands
        self.categories = categories
        self.nutriments = nutriments
        self.servingSize = servingSize
        self.servingQuantity = servingQuantity
        self.imageURL = imageURL
        self.imageFrontURL = imageFrontURL
        self.code = code
        self.dataSource = dataSource
    }

    init(
        id: String,
        productName: String,
        brands: String,
        nutriments: Nutriments,
        servingSize: String,
        imageURL: String?
    ) {
        self.init(
            id: id,
            productName: productName,
            brands: brands,
            categories: nil,
            nutriments: nutriments,
            servingSize: servingSize,
            servingQuantity: 100.0,
            imageURL: imageURL,
            imageFrontURL: imageURL,
            code: nil
        )
    }

    var displayName: String {
        if let productName = productName, !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return productName
        } else if let brands = brands, !brands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return brands
        } else {
            return NSLocalizedString("Unknown Product", comment: "Fallback name for products without names")
        }
    }

    var hasSufficientNutritionalData: Bool {
        nutriments.carbohydrates != nil && !displayName.isEmpty
    }

    // MARK: - Hashable & Equatable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: OpenFoodFactsProduct, rhs: OpenFoodFactsProduct) -> Bool {
        lhs.id == rhs.id
    }
}

extension OpenFoodFactsProduct: Codable {
    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case categories
        case nutriments
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case imageURL = "image_url"
        case imageFrontURL = "image_front_url"
        case code
        case dataSource = "data_source"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle product identification
        let code = try container.decodeIfPresent(String.self, forKey: .code)
        let productName = try container.decodeIfPresent(String.self, forKey: .productName)

        // Generate ID from barcode or create synthetic one
        if let code = code {
            id = code
            self.code = code
        } else {
            // Create synthetic ID for products without barcodes
            let name = productName ?? "unknown"
            id = "synthetic_\(abs(name.hashValue))"
            self.code = nil
        }

        self.productName = productName
        brands = try container.decodeIfPresent(String.self, forKey: .brands)
        categories = try container.decodeIfPresent(String.self, forKey: .categories)
        // Handle nutriments with fallback
        nutriments = (try? container.decode(Nutriments.self, forKey: .nutriments)) ?? Nutriments.empty()
        servingSize = try container.decodeIfPresent(String.self, forKey: .servingSize)
        // Handle serving_quantity which can be String or Double
        if let servingQuantityDouble = try? container.decodeIfPresent(Decimal.self, forKey: .servingQuantity) {
            servingQuantity = servingQuantityDouble
        } else if let servingQuantityString = try? container.decodeIfPresent(String.self, forKey: .servingQuantity) {
            servingQuantity = Decimal(from: servingQuantityString)
        } else {
            servingQuantity = nil
        }
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        imageFrontURL = try container.decodeIfPresent(String.self, forKey: .imageFrontURL)
        // dataSource has a default value, but override if present in decoded data
        if let decodedDataSource = try? container.decode(FoodDataSource.self, forKey: .dataSource) {
            dataSource = decodedDataSource
        } else {
            dataSource = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(brands, forKey: .brands)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encode(nutriments, forKey: .nutriments)
        try container.encodeIfPresent(servingSize, forKey: .servingSize)
        try container.encodeIfPresent(servingQuantity, forKey: .servingQuantity)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(imageFrontURL, forKey: .imageFrontURL)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encode(dataSource, forKey: .dataSource)
    }
}

struct Nutriments: Codable {
    // MARK: - Macro nutrients

    let carbohydrates: Decimal?
    let proteins: Decimal?
    let fat: Decimal?
    let calories: Decimal?
    let sugars: Decimal?
    let fiber: Decimal?
    let energy: Decimal?

    /// Raw-ish OpenFoodFacts micronutrient key → raw value.
    /// Keep unit/context suffixes so normalization can be correct.
    ///
    /// Examples:
    /// - calcium_100g
    /// - vitamin_d_100g
    /// - vitamin_d_value
    /// - vitamin_b12_100g
    let micronutrients: [String: Decimal]

    enum CodingKeys: String, CodingKey {
        case carbohydrates100g = "carbohydrates_100g"
        case proteins100g = "proteins_100g"
        case fat100g = "fat_100g"
        case calories100g = "energy-kcal_100g"
        case sugars100g = "sugars_100g"
        case fiber100g = "fiber_100g"
        case energy100g = "energy_100g"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        carbohydrates = try container.decodeFlexibleDecimalIfPresent(forKey: .carbohydrates100g)
        proteins = try container.decodeFlexibleDecimalIfPresent(forKey: .proteins100g)
        fat = try container.decodeFlexibleDecimalIfPresent(forKey: .fat100g)
        calories = try container.decodeFlexibleDecimalIfPresent(forKey: .calories100g)
        sugars = try container.decodeFlexibleDecimalIfPresent(forKey: .sugars100g)
        fiber = try container.decodeFlexibleDecimalIfPresent(forKey: .fiber100g)
        energy = try container.decodeFlexibleDecimalIfPresent(forKey: .energy100g)

        let raw = (try? decoder.singleValueContainer().decode([String: AnyDecodable].self)) ?? [:]

        var micros: [String: Decimal] = [:]

        for (rawKey, rawValue) in raw {
            let key = rawKey
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")

            guard let decimal = rawValue.decimalValue else {
                continue
            }

            let isMicronutrientCandidate =
                key.hasSuffix("_100g") ||
                key.hasSuffix("_value")

            guard isMicronutrientCandidate else {
                continue
            }

            if Self.isMacroOrNonMicroKey(key) {
                continue
            }

            if MicroNutrient(openFoodFactsKey: key) == nil {
                continue
            }

            micros[key] = decimal
        }

        micronutrients = micros

        #if DEBUG
            debugLogVitaminKeys(raw)
            debugLogMappedMicronutrients(micros)
        #endif
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(carbohydrates, forKey: .carbohydrates100g)
        try container.encodeIfPresent(proteins, forKey: .proteins100g)
        try container.encodeIfPresent(fat, forKey: .fat100g)
        try container.encodeIfPresent(calories, forKey: .calories100g)
        try container.encodeIfPresent(sugars, forKey: .sugars100g)
        try container.encodeIfPresent(fiber, forKey: .fiber100g)
        try container.encodeIfPresent(energy, forKey: .energy100g)
    }

    init(
        carbohydrates: Decimal?,
        proteins: Decimal?,
        fat: Decimal?,
        calories: Decimal?,
        sugars: Decimal?,
        fiber: Decimal?,
        energy: Decimal?,
        micronutrients: [String: Decimal] = [:]
    ) {
        self.carbohydrates = carbohydrates
        self.proteins = proteins
        self.fat = fat
        self.calories = calories
        self.sugars = sugars
        self.fiber = fiber
        self.energy = energy
        self.micronutrients = micronutrients
    }

    static func empty() -> Nutriments {
        Nutriments(
            carbohydrates: 0,
            proteins: nil,
            fat: nil,
            calories: nil,
            sugars: nil,
            fiber: nil,
            energy: nil,
            micronutrients: [:]
        )
    }

    // Exclusion filter for micro nutrients. To Do: is there a less verbose or simpler method?
    private static func isMacroOrNonMicroKey(_ key: String) -> Bool {
        key.contains("carbohydrates") ||
            key.contains("proteins") ||
            key.contains("protein") ||
            key.contains("fat") ||
            key.contains("energy") ||
            key.contains("sugars") ||
            key.contains("fiber") ||
            key.contains("saturated") ||
            key.contains("trans_fat") ||
            key.contains("cholesterol") ||
            key.contains("alcohol") ||
            key.contains("sodium")
    }

    // MARK: - Debug

    #if DEBUG
        private func debugLogVitaminKeys(_ raw: [String: AnyDecodable]) {
            for key in raw.keys.sorted() {
                let k = key.lowercased()
                if k.contains("vitamin") ||
                    k.contains("riboflavin") ||
                    k.contains("thiamin") ||
                    k.contains("pantothenic") ||
                    k.contains("b12") ||
                    k.contains("folate") ||
                    k.contains("biotin")
                {
                    print("🧪 OFF raw vitamin key:", key, "=", raw[key]?.value ?? "")
                }
            }
        }

        private func debugLogMappedMicronutrients(_ micros: [String: Decimal]) {
            if micros.isEmpty {
                print("⚠️ OFF micronutrients: none mapped for this product")
            } else {
                for (key, value) in micros.sorted(by: { $0.key < $1.key }) {
                    print("✅ OFF mapped micronutrient candidate:", key, "=", value)
                }
            }
        }
    #endif
}

struct AnyDecodable: Decodable {
    let value: Any

    var decimalValue: Decimal? {
        if let decimal = value as? Decimal {
            return decimal
        }

        if let double = value as? Double {
            return Decimal(double)
        }

        if let int = value as? Int {
            return Decimal(int)
        }

        if let string = value as? String {
            return Decimal(string: string.replacingOccurrences(of: ",", with: "."))
        }

        return nil
    }

    var stringValue: String? {
        value as? String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let decimal = try? container.decode(Decimal.self) {
            value = decimal
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if container.decodeNil() {
            value = ""
        } else {
            value = ""
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let decimal = try? decodeIfPresent(Decimal.self, forKey: key) {
            return decimal
        }

        if let double = try? decodeIfPresent(Double.self, forKey: key) {
            return Decimal(double)
        }

        if let int = try? decodeIfPresent(Int.self, forKey: key) {
            return Decimal(int)
        }

        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Decimal(string: string.replacingOccurrences(of: ",", with: "."))
        }

        return nil
    }
}

enum OpenFoodFactsError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case decodingError(Error)
    case networkError(Error)
    case productNotFound
    case invalidBarcode
    case rateLimitExceeded
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid API URL", comment: "Error message for invalid OpenFoodFacts URL")
        case .invalidResponse:
            return NSLocalizedString("Invalid API response", comment: "Error message for invalid OpenFoodFacts response")
        case .noData:
            return NSLocalizedString("No data received", comment: "Error message when no data received from OpenFoodFacts")
        case let .decodingError(error):
            return String(
                format: NSLocalizedString("Failed to decode response: %@", comment: "Error message for JSON decoding failure"),
                error.localizedDescription
            )
        case let .networkError(error):
            return String(
                format: NSLocalizedString("Network error: %@", comment: "Error message for network failures"),
                error.localizedDescription
            )
        case .productNotFound:
            return NSLocalizedString(
                "Product not found",
                comment: "Error message when product is not found in OpenFoodFacts database"
            )
        case .invalidBarcode:
            return NSLocalizedString("Invalid barcode format", comment: "Error message for invalid barcode")
        case .rateLimitExceeded:
            return NSLocalizedString("Too many requests. Please try again later.", comment: "Error message for API rate limiting")
        case let .serverError(code):
            return String(format: NSLocalizedString("Server error (%d)", comment: "Error message for server errors"), code)
        }
    }

    var failureReason: String? {
        switch self {
        case .invalidURL:
            return "The OpenFoodFacts API URL is malformed"
        case .invalidResponse:
            return "The API response format is invalid"
        case .noData:
            return "The API returned no data"
        case .decodingError:
            return "The API response format is unexpected"
        case .networkError:
            return "Network connectivity issue"
        case .productNotFound:
            return "The barcode or product is not in the database"
        case .invalidBarcode:
            return "The barcode format is not valid"
        case .rateLimitExceeded:
            return "API usage limit exceeded"
        case .serverError:
            return "OpenFoodFacts server is experiencing issues"
        }
    }
}

extension Nutriments {
    func toMicronutrientValues() -> [MicronutrientValue] {
        micronutrients.compactMap { rawKey, rawValue in
            guard let micro = MicroNutrient(openFoodFactsKey: rawKey) else {
                print("⚠️ Unmapped micronutrient:", rawKey, "=", rawValue)
                return nil
            }

            let normalized = normalizeOpenFoodFactsValue(
                rawValue,
                rawKey: rawKey,
                micro: micro
            )

            print("✅ Micro:", rawKey, "raw:", rawValue, "→", micro.displayName, normalized, micro.unit)

            return MicronutrientValue(
                substance: micro,
                amount: normalized,
                amountPer100: normalized
            )
        }
        .filter({ $0.amount > 0.01 }) // To Do: shouldn't be needed here
        .sorted { $0.name < $1.name }
        .uniqued(on: { $0.substance.displayName }) // Removes duplicates. Would be better if not needed...
    }

    private func normalizeOpenFoodFactsValue(
        _ value: Decimal,
        rawKey: String,
        micro: MicroNutrient
    ) -> Decimal {
        let key = rawKey
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if key.hasSuffix("_value") {
            return value
        }

        if key.contains("_mg_100g") {
            switch micro.unit {
            case "ug",
                 "µg":
                return value * 1000
            default:
                return value
            }
        }

        if key.contains("_µg_100g") || key.contains("_ug_100g") {
            switch micro.unit {
            case "mg":
                return value / 1000
            default:
                return value
            }
        }

        if key.contains("_g_100g") {
            switch micro.unit {
            case "mg":
                return value * 1000
            case "ug",
                 "µg":
                return value * 1_000_000
            default:
                return value
            }
        }

        switch micro.unit {
        case "mg":
            return value * 1000
        case "ug",
             "µg":
            return value * 1_000_000
        default:
            return value
        }
    }
}

extension OpenFoodFactsProduct {
    var micronutrientValues: [MicronutrientValue] {
        nutriments.toMicronutrientValues()
    }
}

extension OpenFoodFactsProduct {
    func toFoodItemDetailed() -> FoodItemDetailed {
        FoodItemDetailed(
            name: displayName,
            nutrition: .per100(
                values: [
                    .carbs: nutriments.carbohydrates ?? 0,
                    .protein: nutriments.proteins ?? 0,
                    .fat: nutriments.fat ?? 0,
                    .fiber: nutriments.fiber ?? 0,
                    .sugars: nutriments.sugars ?? 0
                ],
                portionSize: 100
            ),
            micronutrients: micronutrientValues,
            source: .database
        )
    }
}

extension MicroNutrient {
    init?(openFoodFactsKey rawKey: String) {
        var key = rawKey
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        key = key
            .replacingOccurrences(of: "_100g", with: "")
            .replacingOccurrences(of: "_serving", with: "")
            .replacingOccurrences(of: "_value", with: "")
            .replacingOccurrences(of: "_unit", with: "")
            .replacingOccurrences(of: "_mg", with: "")
            .replacingOccurrences(of: "_µg", with: "")
            .replacingOccurrences(of: "_ug", with: "")
            .replacingOccurrences(of: "_g", with: "")

        switch key {
        case "vitamin_a",
             "vitamin_a_rae":
            self = .vitaminA
        case "thiamin",
             "thiamine",
             "vitamin_b1":
            self = .vitaminB1
        case "riboflavin",
             "vitamin_b2":
            self = .vitaminB2
        case "niacin",
             "vitamin_b3":
            self = .vitaminB3
        case "pantothenate",
             "pantothenic_acid",
             "vitamin_b5":
            self = .vitaminB5
        case "vitamin_b6":
            self = .vitaminB6
        case "biotin",
             "vitamin_b7":
            self = .vitaminB7
        case "folate",
             "folate_total",
             "folic_acid",
             "vitamin_b9":
            self = .vitaminB9
        case "vitamin_b12":
            self = .vitaminB12
        case "ascorbic_acid",
             "vitamin_c":
            self = .vitaminC
        case "vitamin_d":
            self = .vitaminD
        case "tocopherol",
             "vitamin_e":
            self = .vitaminE
        case "vitamin_k":
            self = .vitaminK

        case "calcium":
            self = .calcium
        case "iron":
            self = .iron
        case "magnesium":
            self = .magnesium
        case "phosphorous",
             "phosphorus":
            self = .phosphorus
        case "potassium":
            self = .potassium
        case "sodium":
            self = .sodium
        case "zinc":
            self = .zinc
        case "copper":
            self = .copper
        case "manganese":
            self = .manganese
        case "selenium":
            self = .selenium
        case "iodide",
             "iodine":
            self = .iodine
        case "salt":
            self = .salt

        default:
            return nil
        }
    }
}
