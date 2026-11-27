@testable import FreeAPS
import UIKit
import XCTest

/// Tests for the AI food analysis pipeline: the response schema sent to the providers (offline),
/// and real requests against each configured provider (integration, skipped without keys).
///
/// Integration setup, none of it committed:
/// Every setting below is read from the environment first, then from `NAME=value` lines in a
/// `.temp/ai-tokens.env` file at the repository root (gitignored):
/// - API keys: `IAPS_AI_TEST_CLAUDE_KEY`, `IAPS_AI_TEST_GEMINI_KEY`, `IAPS_AI_TEST_OPENAI_KEY`.
///   A provider without a key is skipped.
/// - Photo: `IAPS_AI_TEST_PHOTO` (path), default `.temp/ai-test-photo.jpg` at the repository root.
/// - Models: `IAPS_AI_TEST_MODELS` = `default` (each provider's default model, the default),
///   `all` (every non-legacy model), or a comma-separated list of serialized models such as
///   `gemini/gemini-3.8-flash,claude/claude-haiku-5-5`.
final class AIFoodAnalysisTests: XCTestCase {
    // MARK: - Response schema (offline)

    func testStrictSchemaRequiresEveryPropertyAndAllowsNullForOptionalOnes() throws {
        let schema = try jsonObject(
            AIResponseSchema(object: AIAnalysisResult.schemaVisual, languageInstruction: "in English")
                .jsonSchema(dialect: .strict)
        )

        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertEqual(Set(required), Set(properties.keys), "strict mode lists every property as required")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)

        let imageType = try XCTUnwrap(properties["image_type"] as? [String: Any])
        XCTAssertEqual(imageType["type"] as? String, "string", "a required enum is a plain string")
        XCTAssertEqual(imageType["enum"] as? [String], ImageAnalysisType.allCases.map(\.rawValue))

        let overall = try XCTUnwrap(properties["overall_description"] as? [String: Any])
        XCTAssertEqual(overall["type"] as? [String], ["string", "null"], "an optional property allows null")
        XCTAssertEqual(overall["description"] as? String, "describe what you see on the photo; in English")

        let items = try XCTUnwrap(properties["food_items"] as? [String: Any])
        XCTAssertEqual(items["type"] as? String, "array")
        let item = try XCTUnwrap(items["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(item["properties"] as? [String: Any])
        let itemRequired = try XCTUnwrap(item["required"] as? [String])
        XCTAssertEqual(Set(itemRequired), Set(itemProperties.keys))
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        XCTAssertEqual((itemProperties["name"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual((itemProperties["carbs_per_100"] as? [String: Any])?["type"] as? [String], ["number", "null"])
        XCTAssertEqual((itemProperties["units"] as? [String: Any])?["enum"] as? [String], ["grams", "milliliters"])
        XCTAssertNotNil(itemProperties[MicroNutrient.allCases[0].codingKey], "micronutrients are part of the schema")
    }

    func testLenientSchemaListsOnlyRequiredProperties() throws {
        let schema = try jsonObject(
            AIResponseSchema(object: AIAnalysisResult.schemaText, languageInstruction: "in English")
                .jsonSchema(dialect: .lenient)
        )

        XCTAssertEqual(schema["required"] as? [String], ["food_items"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNil(properties["image_type"], "text analysis has no image type")
        XCTAssertEqual((properties["overall_description"] as? [String: Any])?["type"] as? String, "string")

        let item = try XCTUnwrap((properties["food_items"] as? [String: Any])?["items"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(item["required"] as? [String])), ["name", "confidence", "units"])
        XCTAssertEqual(
            (try XCTUnwrap(item["properties"] as? [String: Any])["carbs_per_100"] as? [String: Any])?["type"] as? String,
            "number"
        )
    }

    func testSerializedSchemaKeepsDefinitionOrderAndSurvivesEncoding() throws {
        let schema = AIResponseSchema(object: AIAnalysisResult.schemaVisual, languageInstruction: "in English")
            .jsonSchema(dialect: .lenient)
        let text = schema.serialized()
        let positions = try ["\"image_type\"", "\"food_items\"", "\"overall_description\"", "\"brief_description\""]
            .map { try XCTUnwrap(text.range(of: $0)?.lowerBound) }
        XCTAssertEqual(positions, positions.sorted(), "properties must be serialized in definition order")
        XCTAssertTrue(text.contains("\"description\":\"describe what you see on the photo; in English\""))

        struct Body: Encodable {
            let model: String
            let schema: OrderedJSON
        }
        let ordered = OrderedJSON(schema)
        let data = try OrderedJSON.encode(Body(model: "m", schema: ordered), splicing: [ordered])
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decoded["model"] as? String, "m")
        XCTAssertEqual((decoded["schema"] as? [String: Any])?["type"] as? String, "object", "the placeholder was replaced")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("ordered-json:"))
    }

    func testPromptExampleRendersFoodItemsAsArray() throws {
        let prompt = try AIPrompts.getAnalysisPrompt(.query("banana"), responseSchema: AIAnalysisResult.schemaText)
        XCTAssertTrue(prompt.text.contains("\"food_items\": [\n"), "the example object must show food_items as an array")
        XCTAssertFalse(prompt.text.contains("(language)"), "the language placeholder is substituted")
        XCTAssertFalse(prompt.responseSchema.languageInstruction.isEmpty)
    }

    /// The answer is stored as it is: each micronutrient is asked in the unit stored, salt as salt.
    func testMicronutrientsAreAskedInTheStoredUnit() throws {
        let schema = try jsonObject(
            AIResponseSchema(object: AIAnalysisResult.schemaText, languageInstruction: "in English")
                .jsonSchema(dialect: .lenient)
        )
        let item = try XCTUnwrap(
            ((schema["properties"] as? [String: Any])?["food_items"] as? [String: Any])?["items"] as? [String: Any]
        )
        let properties = try XCTUnwrap(item["properties"] as? [String: Any])
        func description(_ nutrient: MicroNutrient) -> String? {
            (properties[nutrient.codingKey] as? [String: Any])?["description"] as? String
        }
        XCTAssertEqual(description(.salt), "decimal, Salt in g per 100g/ml (salt, not sodium)")
        XCTAssertEqual(description(.vitaminC), "decimal, Vitamin C in mg per 100g/ml")
        XCTAssertEqual(description(.vitaminD), "decimal, Vitamin D in µg per 100g/ml")
    }

    // MARK: - Food databases: sodium as salt (offline)

    /// USDA lists sodium in mg: stored as salt in g, × 2.5. By the legacy number and by the name (the search's
    /// `nutrientId` 1093 isn't a known code).
    func testUSDASodiumIsStoredAsSalt() throws {
        let byNumber = USDAFoodNutrient(nutrientId: nil, nutrientNumber: "307", nutrientName: nil, value: 400, unitName: "MG")
        let byName = USDAFoodNutrient(
            nutrientId: 1093,
            nutrientNumber: nil,
            nutrientName: "Sodium, Na",
            value: 400,
            unitName: "MG"
        )
        for nutrient in [byNumber, byName] {
            XCTAssertEqual(nutrient.resolvedMicroNutrient, .salt)
            XCTAssertEqual(try XCTUnwrap(nutrient.normalizedValue(for: .salt)), 1)
        }
        // another mineral in mg is only normalised
        let potassium = USDAFoodNutrient(nutrientId: nil, nutrientNumber: "306", nutrientName: nil, value: 400, unitName: "MG")
        XCTAssertEqual(potassium.resolvedMicroNutrient, .potassium)
        XCTAssertEqual(potassium.normalizedValue(for: .potassium), 400)
    }

    /// Open Food Facts lists both: salt is read as salt, and sodium (× 2.5, from g) only without a salt. `x_100g` is
    /// in g whatever unit was entered (`x_unit` / `x_value`).
    func testOpenFoodFactsReadsSaltAndSodiumOnlyWithoutIt() throws {
        func salt(_ json: String) throws -> Decimal? {
            let nutriments = try JSONDecoder().decode(Nutriments.self, from: Data(json.utf8))
            XCTAssertLessThanOrEqual(nutriments.micronutrient.filter { $0.substance == .salt }.count, 1)
            return nutriments.micronutrient.first { $0.substance == .salt }?.amountPer100
        }
        XCTAssertEqual(
            try salt(#"{"carbohydrates_100g": 10, "sodium": 0.4, "sodium_100g": 0.4, "sodium_unit": "mg", "sodium_value": 400}"#),
            1
        )
        XCTAssertEqual(
            try salt(
                #"{"carbohydrates_100g": 10, "salt": 2, "salt_100g": 2, "salt_unit": "g", "salt_value": 2, "sodium": 0.8, "sodium_100g": 0.8, "sodium_unit": "g", "sodium_value": 0.8}"#
            ),
            2
        )
        XCTAssertNil(try salt(#"{"carbohydrates_100g": 10}"#))
    }

    /// A product's `nutriments` as Open Food Facts returns them (a fortified cereal, 30 g serving): every nutrient
    /// under its bare key, `_100g`, `_serving` (all in g), and the entered `_value` / `_unit`. Micronutrients are read
    /// per 100 g only (never the serving, whatever the key order), from g into the stored unit; the macros are as listed.
    func testOpenFoodFactsMicronutrientsArePer100GramsFromGrams() throws {
        let json = #"""
        {
          "carbohydrates": 84, "carbohydrates_100g": 84, "carbohydrates_serving": 25.2,
          "carbohydrates_unit": "g", "carbohydrates_value": 84,
          "energy": 1582, "energy_100g": 1582, "energy_serving": 475, "energy_unit": "kJ", "energy_value": 1582,
          "energy-kcal": 378, "energy-kcal_100g": 378, "energy-kcal_serving": 113,
          "energy-kcal_unit": "kcal", "energy-kcal_value": 378,
          "fat": 0.9, "fat_100g": 0.9, "fat_serving": 0.27, "fat_unit": "g", "fat_value": 0.9,
          "fiber": 3, "fiber_100g": 3, "fiber_serving": 0.9, "fiber_unit": "g", "fiber_value": 3,
          "proteins": 7, "proteins_100g": 7, "proteins_serving": 2.1, "proteins_unit": "g", "proteins_value": 7,
          "sugars": 8, "sugars_100g": 8, "sugars_serving": 2.4, "sugars_unit": "g", "sugars_value": 8,
          "salt": 1.13, "salt_100g": 1.13, "salt_serving": 0.339, "salt_unit": "g", "salt_value": 1.13,
          "sodium": 0.452, "sodium_100g": 0.452, "sodium_serving": 0.1356, "sodium_unit": "g", "sodium_value": 0.452,
          "iron_serving": 0.0024, "iron": 0.008, "iron_100g": 0.008, "iron_unit": "mg", "iron_value": 8,
          "iron_label": "Iron",
          "vitamin-b1_serving": 0.000273, "vitamin-b1": 0.00091, "vitamin-b1_100g": 0.00091,
          "vitamin-b1_unit": "mg", "vitamin-b1_value": 0.91,
          "vitamin-d_serving": 1.26e-06, "vitamin-d": 4.2e-06, "vitamin-d_100g": 4.2e-06,
          "vitamin-d_unit": "µg", "vitamin-d_value": 4.2,
          "vitamin-a": 0.0003, "vitamin-a_100g": 0.0003, "vitamin-a_serving": 0.00009,
          "vitamin-a_unit": "IU", "vitamin-a_value": 1000,
          "vitamin-c_prepared": 0.05, "vitamin-c_prepared_100g": 0.05,
          "nova-group": 4, "nova-group_100g": 4, "nova-group_serving": 4,
          "nutrition-score-fr": 3, "nutrition-score-fr_100g": 3
        }
        """#
        let nutriments = try JSONDecoder().decode(Nutriments.self, from: Data(json.utf8))
        let micros = Dictionary(grouping: nutriments.micronutrient, by: \.substance)
        XCTAssertTrue(micros.values.allSatisfy { $0.count == 1 })
        func per100(_ nutrient: MicroNutrient) -> Decimal? {
            micros[nutrient]?.first?.amountPer100
        }
        XCTAssertEqual(per100(.iron), 8, "mg")
        XCTAssertEqual(per100(.vitaminB1), Decimal(string: "0.91"), "mg")
        XCTAssertEqual(per100(.vitaminD), Decimal(string: "4.2"), "µg")
        XCTAssertEqual(per100(.vitaminA), 300, "µg, from IU by OFF")
        XCTAssertEqual(per100(.salt), Decimal(string: "1.13"), "salt, not the sodium")
        XCTAssertNil(per100(.vitaminC), "a prepared value isn't the product's")
        XCTAssertEqual(Set(micros.keys), [.iron, .vitaminB1, .vitaminD, .vitaminA, .salt])
        XCTAssertTrue(nutriments.micronutrient.allSatisfy { $0.amount == $0.amountPer100 })

        XCTAssertEqual(nutriments.carbohydrates, 84)
        XCTAssertEqual(nutriments.calories, 378)
        XCTAssertEqual(nutriments.energy, 1582)
        XCTAssertEqual(nutriments.fiber, 3)

        // only a per-serving value (a label without a serving quantity): not read as per 100 g
        let servingOnly = try JSONDecoder().decode(
            Nutriments.self,
            from: Data(#"{"carbohydrates_100g": 10, "iron_serving": 0.0024, "iron_unit": "mg", "iron_value": 2.4}"#.utf8)
        )
        XCTAssertTrue(servingOnly.micronutrient.isEmpty)
    }

    /// A label entered per serving (`nutrition_data_per` "serving", 30 g): the bare keys are the serving's, `_100g`
    /// OFF's per 100 g. Read per 100 g, macros and micronutrients alike.
    func testOpenFoodFactsServingLabelIsReadPer100Grams() throws {
        let json = #"""
        {
          "nutrition_data_per": "serving", "serving_quantity": 30,
          "carbohydrates": 25.2, "carbohydrates_100g": 84, "carbohydrates_serving": 25.2,
          "carbohydrates_unit": "g", "carbohydrates_value": 25.2,
          "fiber": 0.9, "fiber_100g": 3, "fiber_serving": 0.9,
          "iron": 0.0024, "iron_100g": 0.008, "iron_serving": 0.0024, "iron_unit": "mg", "iron_value": 2.4,
          "salt": 0.339, "salt_100g": 1.13, "salt_serving": 0.339, "salt_unit": "g", "salt_value": 0.339
        }
        """#
        let nutriments = try JSONDecoder().decode(Nutriments.self, from: Data(json.utf8))
        XCTAssertEqual(nutriments.carbohydrates, 84)
        XCTAssertEqual(nutriments.fiber, 3)
        let micros = Dictionary(grouping: nutriments.micronutrient, by: \.substance)
        XCTAssertEqual(Set(micros.keys), [.iron, .salt])
        XCTAssertEqual(micros[.iron]?.first?.amountPer100, 8, "mg per 100 g, not the serving's 2.4")
        XCTAssertEqual(micros[.salt]?.first?.amountPer100, Decimal(string: "1.13"))
    }

    /// Open Food Facts' niacin is also `vitamin-pp`, and folate `folates`: read as B3 and B9, one value each, the
    /// vitamin's own key first (`vitamin-b3`, `vitamin-b9`) whatever the order.
    func testOpenFoodFactsNiacinAndFolateKeys() throws {
        func per100(_ json: String, _ nutrient: MicroNutrient) throws -> Decimal? {
            let nutriments = try JSONDecoder().decode(Nutriments.self, from: Data(json.utf8))
            let values = nutriments.micronutrient.filter { $0.substance == nutrient }
            XCTAssertLessThanOrEqual(values.count, 1)
            return values.first?.amountPer100
        }
        XCTAssertEqual(try per100(#"{"carbohydrates_100g": 10, "vitamin-pp_100g": 0.016}"#, .vitaminB3), 16, "mg")
        XCTAssertEqual(
            try per100(#"{"carbohydrates_100g": 10, "vitamin-pp_100g": 0.016, "vitamin-b3_100g": 0.01}"#, .vitaminB3),
            10
        )
        XCTAssertEqual(
            try per100(#"{"carbohydrates_100g": 10, "folates_100g": 0.0003}"#, .vitaminB9),
            Decimal(string: "0.3"),
            "mg"
        )
        for json in [
            #"{"carbohydrates_100g": 10, "vitamin-b9_100g": 0.0002, "folates_100g": 0.0003}"#,
            #"{"carbohydrates_100g": 10, "folates_100g": 0.0003, "vitamin-b9_100g": 0.0002}"#
        ] {
            XCTAssertEqual(try per100(json, .vitaminB9), Decimal(string: "0.2"), json)
        }
    }

    /// USDA lists vitamin A as RAE and as IU, and folate as DFE and as the total: one value each, the RAE (the IU has
    /// no factor to µg RAE: never read) and the DFE (the total only without it). A row in a unit not known is left out
    /// (sodium isn't × 2.5'd as it is). Amounts by their shortest description.
    func testUSDAOneValuePerSubstance() throws {
        func row(_ number: String, _ value: Double, _ unit: String, name: String? = nil) -> USDAFoodNutrient {
            USDAFoodNutrient(nutrientId: nil, nutrientNumber: number, nutrientName: name, value: value, unitName: unit)
        }
        let micros = USDAFoodNutrient.micronutrients([
            row("318", 1000, "IU"),
            row("320", 50, "UG"),
            row("417", 60, "UG"),
            row("435", 100, "UG"),
            row("307", 400, "XYZ"),
            row("306", 400, "MG")
        ])
        XCTAssertEqual(micros.map(\.substance), [.vitaminA, .vitaminB9, .potassium])
        XCTAssertEqual(micros.first { $0.substance == .vitaminA }?.amountPer100, 50, "µg RAE")
        XCTAssertEqual(micros.first { $0.substance == .vitaminB9 }?.amountPer100, Decimal(string: "0.1"), "mg, the DFE")

        // the IU alone: no vitamin A; the total alone: the folate; by name as by number
        let alone = USDAFoodNutrient.micronutrients([
            row("318", 1000, "IU"),
            USDAFoodNutrient(nutrientId: 1104, nutrientNumber: nil, nutrientName: "Vitamin A, IU", value: 1000, unitName: "IU"),
            row("417", 60, "UG")
        ])
        XCTAssertEqual(alone.map(\.substance), [.vitaminB9])
        XCTAssertEqual(alone.first?.amountPer100, Decimal(string: "0.06"))
        // folate by name: the DFE first, wherever listed
        let byName = USDAFoodNutrient.micronutrients([
            USDAFoodNutrient(nutrientId: 1, nutrientNumber: nil, nutrientName: "Folate, DFE", value: 100, unitName: "UG"),
            USDAFoodNutrient(nutrientId: 2, nutrientNumber: nil, nutrientName: "Folate, total", value: 60, unitName: "UG")
        ])
        XCTAssertEqual(byName.map(\.amountPer100), [Decimal(string: "0.1")!])

        XCTAssertNil(row("307", 400, "XYZ").normalizedValue(for: .salt))
        XCTAssertEqual(row("205", 0.1, "G").decimalValue, Decimal(string: "0.1"))
        XCTAssertEqual(row("306", 0.0006, "G").normalizedValue(for: .potassium), Decimal(string: "0.6"))
    }

    /// A row as the search returns it: FoodData Central's id, number and name, the unit as listed.
    private func usda(_ id: Int, _ number: String, _ name: String, _ value: Double, _ unit: String) -> USDAFoodNutrient {
        USDAFoodNutrient(nutrientId: id, nutrientNumber: number, nutrientName: name, value: value, unitName: unit)
    }

    /// Energy is read in kcal: SR Legacy lists the kJ row as often first as not (rice milk: 195 kJ, then 47 kcal; the
    /// 195 was the calories), Foundation foods often only Atwater's factors (kcal; the specific before the general), and
    /// a food with only kJ is ÷ 4.184.
    func testUSDAEnergyIsInKcal() throws {
        let kJ = usda(1062, "268", "Energy", 195, "kJ")
        let kcal = usda(1008, "208", "Energy", 47, "KCAL")
        XCTAssertEqual(USDAFoodNutrient.energyKcal([kJ, kcal]), 47)
        XCTAssertEqual(USDAFoodNutrient.energyKcal([kcal, kJ]), 47)
        XCTAssertEqual(USDAMacronutrients([kJ, kcal]).energy, 47)

        let general = usda(2047, "957", "Energy (Atwater General Factors)", 42.8, "KCAL")
        let specific = usda(2048, "958", "Energy (Atwater Specific Factors)", 42.9, "KCAL")
        XCTAssertEqual(USDAFoodNutrient.energyKcal([general, specific]), Decimal(string: "42.9"))
        XCTAssertEqual(USDAFoodNutrient.energyKcal([general]), Decimal(string: "42.8"))
        XCTAssertEqual(USDAFoodNutrient.energyKcal([general, kcal]), 47, "Energy first")

        XCTAssertEqual(USDAFoodNutrient.energyKcal([usda(1062, "268", "Energy", 418.4, "kJ")]), 100)
        XCTAssertNil(USDAFoodNutrient.energyKcal([usda(1062, "268", "Energy", 0, "kJ")]))
        XCTAssertNil(USDAFoodNutrient.energyKcal([usda(1003, "203", "Protein", 3, "G")]))
    }

    /// Sugars are the total ("Total Sugars", SR Legacy and Survey; "Sugars, Total", Foundation), never sucrose (1010,
    /// which was read as the total); the macros are in g.
    func testUSDASugarsAreTheTotal() throws {
        let sucrose = usda(1010, "210", "Sucrose", 2.58, "G")
        XCTAssertEqual(USDAMacronutrients([sucrose]).sugars, 0)
        XCTAssertEqual(
            USDAMacronutrients([usda(1010, "210", "Sucrose", 0, "G"), usda(1063, "269.3", "Sugars, Total", 4.96, "G")]).sugars,
            Decimal(string: "4.96")
        )
        XCTAssertEqual(
            USDAMacronutrients([sucrose, usda(2000, "269", "Total Sugars", 5.28, "G")]).sugars,
            Decimal(string: "5.28")
        )

        let milk = USDAMacronutrients([
            usda(1062, "268", "Energy", 251, "kJ"),
            usda(1003, "203", "Protein", 3.27, "G"),
            usda(1004, "204", "Total lipid (fat)", 3.2, "G"),
            usda(1005, "205", "Carbohydrate, by difference", 4.63, "G"),
            usda(1079, "291", "Fiber, total dietary", 0, "G"),
            usda(1008, "208", "Energy", 60, "KCAL")
        ])
        XCTAssertEqual(milk.carbs, Decimal(string: "4.63"))
        XCTAssertEqual(milk.protein, Decimal(string: "3.27"))
        XCTAssertEqual(milk.fat, Decimal(string: "3.2"))
        XCTAssertEqual(milk.fiber, 0)
        XCTAssertEqual(milk.energy, 60)
        // a macronutrient row not in g isn't read as g
        XCTAssertEqual(USDAMacronutrients([usda(1003, "203", "Protein", 3000, "MG")]).protein, 0)
    }

    /// A unit with a qualifier is its unit (`MG_ATE`, vitamin E as alpha-tocopherol equivalents; `MCG_DFE`); IU is
    /// read for vitamin D only (× 0.025 µg) and only without its µg row; never for vitamin A, nor for another
    /// nutrient (no single factor).
    func testUSDAUnitsWithAQualifierAndVitaminDInIU() throws {
        let vitaminE = USDAFoodNutrient(nutrientId: nil, nutrientNumber: "323", nutrientName: nil, value: 1.5, unitName: "MG_ATE")
        XCTAssertEqual(vitaminE.resolvedMicroNutrient, .vitaminE)
        XCTAssertEqual(vitaminE.normalizedValue(for: .vitaminE), Decimal(string: "1.5"))
        let folate = USDAFoodNutrient(
            nutrientId: 1190,
            nutrientNumber: "435",
            nutrientName: "Folate, DFE",
            value: 100,
            unitName: "MCG_DFE"
        )
        XCTAssertEqual(folate.normalizedValue(for: .vitaminB9), Decimal(string: "0.1"), "mg")
        XCTAssertEqual(
            usda(1109, "323", "Vitamin E (alpha-tocopherol)", 0.26, "MG").normalizedValue(for: .vitaminE),
            Decimal(string: "0.26")
        )
        XCTAssertNil(
            USDAFoodNutrient(nutrientId: nil, nutrientNumber: "323", nutrientName: nil, value: 10, unitName: "IU")
                .normalizedValue(for: .vitaminE)
        )
        XCTAssertNil(usda(1104, "318", "Vitamin A, IU", 1000, "IU").normalizedValue(for: .vitaminA))

        let microgram = usda(1114, "328", "Vitamin D (D2 + D3)", 0.96, "UG")
        let iu = usda(1110, "324", "Vitamin D (D2 + D3), International Units", 38.4, "IU")
        XCTAssertEqual(iu.resolvedMicroNutrient, .vitaminD)
        for rows in [[microgram, iu], [iu, microgram]] {
            let micros = USDAFoodNutrient.micronutrients(rows)
            XCTAssertEqual(micros.map(\.substance), [.vitaminD])
            XCTAssertEqual(micros.first?.amountPer100, Decimal(string: "0.96"), "the µg row")
        }
        let iuOnly = USDAFoodNutrient.micronutrients([usda(1110, "324", "Vitamin D (D2 + D3), International Units", 40, "IU")])
        XCTAssertEqual(iuOnly.first?.amountPer100, 1, "40 IU is 1 µg")
        let byNumber = USDAFoodNutrient(nutrientId: nil, nutrientNumber: "324", nutrientName: nil, value: 40, unitName: "IU")
        XCTAssertEqual(USDAFoodNutrient.micronutrients([byNumber]).first?.amountPer100, 1)
    }

    // MARK: - Live providers (integration)

    func testPhotoAnalysisOnConfiguredProviders() async throws {
        let models = try modelsUnderTest()
        let photo = try samplePhoto()
        let base64 = try await ImageCompression.getImageBase64(for: photo, maxSize: 1024)
        let prompt = try AIPrompts.getAnalysisPrompt(.image(photo, nil), responseSchema: AIAnalysisResult.schemaVisual)

        for (model, apiKey) in models {
            await run(model) {
                try await AIAnalysisService.create(for: model, apiKey: apiKey)
                    .analyzeImage(prompt: prompt, images: [base64], telemetryCallback: nil)
            }
        }
    }

    func testTextAnalysisOnConfiguredProviders() async throws {
        let models = try modelsUnderTest()
        let prompt = try AIPrompts.getAnalysisPrompt(
            .query("one medium banana and three small pears"),
            responseSchema: AIAnalysisResult.schemaText
        )

        for (model, apiKey) in models {
            await run(model) {
                try await AIAnalysisService.create(for: model, apiKey: apiKey)
                    .analyzeText(prompt: prompt, telemetryCallback: nil)
            }
        }
    }

    /// Runs one analysis, records its outcome as an activity, and checks the result is usable.
    /// A failure on one model is reported without stopping the others.
    private func run(_ model: AIModel, _ analysis: () async throws -> FoodItemGroup) async {
        let started = Date()
        do {
            let group = try await analysis()
            let seconds = Date().timeIntervalSince(started)
            let names = group.foodItems.map(\.name).joined(separator: ", ")
            print("[\(model.rawValue)] \(String(format: "%.1f", seconds))s: \(group.foodItems.count) item(s): \(names)")

            XCTAssertFalse(group.foodItems.isEmpty, "[\(model.rawValue)] no food items")
            for item in group.foodItems {
                XCTAssertFalse(item.name.isEmpty, "[\(model.rawValue)] item without a name")
            }
            XCTAssertTrue(
                group.foodItems.contains { $0.nutrition.values[.carbs] != nil },
                "[\(model.rawValue)] no item carries carbohydrates"
            )
        } catch {
            XCTFail("[\(model.rawValue)] failed after \(String(format: "%.1f", Date().timeIntervalSince(started)))s: \(error)")
        }
    }

    // MARK: - Configuration

    private func modelsUnderTest() throws -> [(AIModel, String)] {
        let keys = try apiKeys()
        guard !keys.isEmpty else {
            throw XCTSkip("No AI API keys: set IAPS_AI_TEST_*_KEY or create .temp/ai-tokens.env")
        }

        let selection = setting("IAPS_AI_TEST_MODELS") ?? "default"
        let candidates: [AIModel] = switch selection {
        case "default": keys.keys.map { AIModel.defaultModel(for: $0) }
        case "all": AIModel.allCases.filter { !$0.isDeprecated }
        default: try selection.split(separator: ",").map {
                let raw = $0.trimmingCharacters(in: .whitespaces)
                return try XCTUnwrap(AIModel(rawValue: raw), "unknown model '\(raw)' in IAPS_AI_TEST_MODELS")
            }
        }

        let models = candidates.compactMap { model in keys[model.provider].map { (model, $0) } }
        guard !models.isEmpty else {
            throw XCTSkip("No API key for the selected models (\(selection))")
        }
        return models
    }

    private func apiKeys() throws -> [AIProvider: String] {
        var keys: [AIProvider: String] = [:]
        for (provider, name) in [
            (AIProvider.claude, "IAPS_AI_TEST_CLAUDE_KEY"),
            (AIProvider.gemini, "IAPS_AI_TEST_GEMINI_KEY"),
            (AIProvider.openAI, "IAPS_AI_TEST_OPENAI_KEY")
        ] {
            if let key = setting(name) {
                keys[provider] = key
            }
        }
        return keys
    }

    private func samplePhoto() throws -> UIImage {
        let path = setting("IAPS_AI_TEST_PHOTO")
            ?? repositoryRoot.appendingPathComponent(".temp/ai-test-photo.jpg").path
        guard let image = UIImage(contentsOfFile: path) else {
            throw XCTSkip("No sample photo at \(path): set IAPS_AI_TEST_PHOTO or add .temp/ai-test-photo.jpg")
        }
        return image
    }

    /// A test setting: the environment variable, or the same name in `.temp/ai-tokens.env`.
    private func setting(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name] ?? envFileValues[name]
        let trimmed = value?.trimmingCharacters(in: .whitespaces)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// `NAME=value` lines from `.temp/ai-tokens.env`; blank lines and `#` comments are ignored,
    /// surrounding quotes are stripped.
    private lazy var envFileValues: [String: String] = {
        let envFile = repositoryRoot.appendingPathComponent(".temp/ai-tokens.env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].hasPrefix("#") else { continue }
            values[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return values
    }()

    /// FreeAPSTests/<this file> -> repository root.
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func jsonObject(_ value: JSONValue) throws -> [String: Any] {
        let data = Data(value.serialized().utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
