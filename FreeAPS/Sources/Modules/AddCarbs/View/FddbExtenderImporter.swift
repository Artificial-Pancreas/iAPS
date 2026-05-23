import Foundation

// MARK: - Public types

/// Mode in which nutrition is expressed in the import result
enum FddbResultMode: Equatable {
    case perServing
    case per100(unit: FddbUnit) // 100 g or 100 ml
}

/// Supported mass/volume units for serving sizes and per-100
enum FddbUnit: String, Equatable {
    case grams
    case milliliters
}

/// Minimal nutrition payload for the editor
/// - All macros can be nil if not available
/// - `mode` determines whether values are per-serving or per-100
/// - `standardServingSize` and `standardServingUnit` are set when reliably detected (e.g., "1 Portion = 250 ml")
struct FddbImportResult: Equatable {
    let name: String
    let carbs: Decimal?
    let protein: Decimal?
    let fat: Decimal?
    let calories: Decimal?
    let fiber: Decimal?
    let sugars: Decimal?

    let mode: FddbResultMode
    let standardServingSize: Decimal?
    let standardServingUnit: FddbUnit?
}

// MARK: - Errors

enum FddbImportError: Error, LocalizedError {
    case unsupportedContent
    case noParseableContent
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unsupportedContent: return "Inhalt konnte nicht verarbeitet werden."
        case .noParseableContent: return "Keine verwertbaren Nährwerte gefunden."
        case .invalidURL: return "Ungültige FDDB-Share-URL."
        }
    }
}

// MARK: - Importer

enum FddbExtenderImporter {
    /// Public entry point. Accepts full share URL (e.g. https://share.fddbextender.de/3975627)
    static func importFrom(urlString: String) async throws -> FddbImportResult {
        guard let url = URL(string: urlString) else { throw FddbImportError.invalidURL }

        // Download (headers improve compatibility with some CDNs)
        let data = try await fetchData(url: url)

        // 0) Some share endpoints may return JSON directly – try that first
        if let parsed = parseDirectJSON(data: data) { return parsed }

        // 1) Try parsing as text (UTF-8 first; fallback to ISO Latin-1)
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard !html.isEmpty else { throw FddbImportError.unsupportedContent }

        // 2) Try multiple parse strategies in order
        if let parsed = parseOgDescription(html: html) { return parsed }
        if let parsed = parseJSONLD(html: html) { return parsed }
        if let parsed = parseEmbeddedJSON(html: html) { return parsed }
        if let parsed = parseHTMLLabels(html: html) { return parsed }

        throw FddbImportError.noParseableContent
    }

    // MARK: - Networking

    private static func fetchData(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    // MARK: - Direct JSON

    /// Parse a response that is already JSON (object or array) and extract nutrition if present.
    private static func parseDirectJSON(data: Data) -> FddbImportResult? {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let roots: [[String: Any]]
        if let dict = any as? [String: Any] {
            roots = [dict]
        } else if let arr = any as? [[String: Any]] {
            roots = arr
        } else {
            return nil
        }

        for root in roots {
            let name = (root["title"] as? String) ?? (root["name"] as? String) ?? "Food"
            let nutrition = (root["nutrition"] as? [String: Any]) ?? root

            let carbs = decimal(from: nutrition["carbs"]) ?? decimal(from: nutrition["carbohydrates"]) ??
                decimal(from: nutrition["carbohydrateContent"]) // g
            let protein = decimal(from: nutrition["protein"]) ?? decimal(from: nutrition["proteinContent"]) // g
            let fat = decimal(from: nutrition["fat"]) ?? decimal(from: nutrition["fatContent"]) // g

            let calories = decimal(from: nutrition["calories"]) ?? decimal(from: nutrition["energy"]) // kcal
            let fiber = decimal(from: nutrition["fiber"]) ?? decimal(from: nutrition["fiberContent"]) // g
            let sugars = decimal(from: nutrition["sugars"]) ?? decimal(from: nutrition["sugarContent"]) // g

            // Portions: divide totals to per-serving if present
            let portions = parsePortions(from: root["portions"] ?? root["servings"] ?? root["recipeYield"] ?? root["yield"])

            if carbs != nil || protein != nil || fat != nil || calories != nil {
                let normalized = normalizePerPortion(
                    name: name,
                    carbs: carbs,
                    protein: protein,
                    fat: fat,
                    calories: calories,
                    fiber: fiber,
                    sugars: sugars,
                    portions: portions
                )
                return normalized
            }
        }
        return nil
    }

    // MARK: - og:description Parsing (FDDB Extender specific)

    /// Fast-path for FDDB Extender share pages.
    /// The og:description always contains per-portion macros in the format:
    /// "N Portionen - Xkcal / Ykj pro Portion (A.Bg KH, C.Dg Fett, E.Fg Protein) - Zutaten: …"
    private static func parseOgDescription(html: String) -> FddbImportResult? {
        guard let desc = extractOgDescription(from: html) else { return nil }
        let name = extractName(from: html) ?? "Food"

        let calories = firstRegexGroup(
            in: desc,
            pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*kcal",
            options: [.caseInsensitive]
        ).flatMap { decimal(from: $0) }

        let carbs = firstRegexGroup(
            in: desc,
            pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*g\\s*KH",
            options: [.caseInsensitive]
        ).flatMap { decimal(from: $0) }

        let fat = firstRegexGroup(
            in: desc,
            pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*g\\s*Fett",
            options: [.caseInsensitive]
        ).flatMap { decimal(from: $0) }

        let protein = firstRegexGroup(
            in: desc,
            pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*g\\s*Protein",
            options: [.caseInsensitive]
        ).flatMap { decimal(from: $0) }

        guard carbs != nil || fat != nil || protein != nil else { return nil }

        return FddbImportResult(
            name: name,
            carbs: carbs,
            protein: protein,
            fat: fat,
            calories: calories,
            fiber: nil,
            sugars: nil,
            mode: .perServing,
            standardServingSize: nil,
            standardServingUnit: nil
        )
    }

    private static func extractOgDescription(from html: String) -> String? {
        // property before content (standard order)
        if let desc = firstRegexGroup(
            in: html,
            pattern: "<meta[^>]*property=\"og:description\"[^>]*content=\"([^\"]*)\"",
            options: [.caseInsensitive]
        ) { return desc }
        // content before property (reversed order)
        return firstRegexGroup(
            in: html,
            pattern: "<meta[^>]*content=\"([^\"]*)\"[^>]*property=\"og:description\"",
            options: [.caseInsensitive]
        )
    }

    // MARK: - JSON-LD Parsing

    private static func parseJSONLD(html: String) -> FddbImportResult? {
        guard let jsonLD = extractJSONLD(html: html) else { return nil }

        for root in jsonLD {
            let name = (root["name"] as? String) ?? (root["headline"] as? String) ?? extractName(from: html) ?? "Food"
            let nutrition = root["nutrition"] as? [String: Any] ?? root

            let carbs = decimal(from: nutrition["carbohydrateContent"]) ?? decimal(from: nutrition["carbohydrates"]) ??
                decimal(from: nutrition["carbs"]) // g
            let protein = decimal(from: nutrition["proteinContent"]) ?? decimal(from: nutrition["protein"]) // g
            let fat = decimal(from: nutrition["fatContent"]) ?? decimal(from: nutrition["fat"]) // g

            let calories = decimal(from: nutrition["calories"]) ?? decimal(from: nutrition["energy"]) // kcal
            let fiber = decimal(from: nutrition["fiberContent"]) ?? decimal(from: nutrition["fiber"]) // g
            let sugars = decimal(from: nutrition["sugarContent"]) ?? decimal(from: nutrition["sugars"]) // g

            let portions = parsePortions(from: root["servings"] ?? root["recipeYield"] ?? root["yield"])

            if carbs != nil || protein != nil || fat != nil || calories != nil {
                let normalized = normalizePerPortion(
                    name: name,
                    carbs: carbs,
                    protein: protein,
                    fat: fat,
                    calories: calories,
                    fiber: fiber,
                    sugars: sugars,
                    portions: portions
                )
                return normalized
            }
        }
        return nil
    }

    // MARK: - Embedded JSON Parsing

    private static func parseEmbeddedJSON(html: String) -> FddbImportResult? {
        guard let embeddedJSON = extractEmbeddedJSON(html: html) else { return nil }

        for root in embeddedJSON {
            let name = root["title"] as? String ?? root["name"] as? String ?? extractName(from: html) ?? "Food"
            let nutrition = root["nutrition"] as? [String: Any] ?? root

            let carbs = decimal(from: nutrition["carbs"]) ?? decimal(from: nutrition["carbohydrates"]) ??
                decimal(from: nutrition["carbohydrateContent"]) // g
            let protein = decimal(from: nutrition["protein"]) ?? decimal(from: nutrition["proteinContent"]) // g
            let fat = decimal(from: nutrition["fat"]) ?? decimal(from: nutrition["fatContent"]) // g

            let calories = decimal(from: nutrition["calories"]) ?? decimal(from: nutrition["energy"]) // kcal
            let fiber = decimal(from: nutrition["fiber"]) ?? decimal(from: nutrition["fiberContent"]) // g
            let sugars = decimal(from: nutrition["sugars"]) ?? decimal(from: nutrition["sugarContent"]) // g

            let portions = parsePortions(from: root["portions"] ?? root["servings"] ?? root["recipeYield"] ?? root["yield"])

            if carbs != nil || protein != nil || fat != nil || calories != nil {
                let normalized = normalizePerPortion(
                    name: name,
                    carbs: carbs,
                    protein: protein,
                    fat: fat,
                    calories: calories,
                    fiber: fiber,
                    sugars: sugars,
                    portions: portions
                )
                return normalized
            }
        }
        return nil
    }

    // MARK: - HTML Parsing (labels)

    /// Fallback: parse plain HTML with German labels and detect either per-serving totals (with portions) or explicit per-100 blocks.
    private static func parseHTMLLabels(html: String) -> FddbImportResult? {
        let name = extractName(from: html) ?? "Food"

        // 1) Prefer a dedicated "per portion" section if present
        if let range = firstRegexRange(in: html, pattern: "(pro\\s*Portion|je\\s*Portion)", options: [.caseInsensitive]) {
            let section = slice(html, around: range, before: 300, after: 1200)
            let m = parseMacros(in: section)
            if m.carbs != nil || m.protein != nil || m.fat != nil || m.calories != nil {
                let serving = detectStandardServing(in: html)
                return FddbImportResult(
                    name: name,
                    carbs: m.carbs,
                    protein: m.protein,
                    fat: m.fat,
                    calories: m.calories,
                    fiber: m.fiber,
                    sugars: m.sugars,
                    mode: .perServing,
                    standardServingSize: serving?.size,
                    standardServingUnit: serving?.unit
                )
            }
        }

        // 2) Otherwise, look for an explicit per-100 section
        if let range = firstRegexRange(
            in: html,
            pattern: "((?:pro|je)\\s*100\\s*(?:g|ml)|100\\s*(?:g|ml)|100(?:g|ml))",
            options: [.caseInsensitive]
        ) {
            let section = slice(html, around: range, before: 300, after: 1200)
            let m = parseMacros(in: section)
            if m.carbs != nil || m.protein != nil || m.fat != nil || m.calories != nil {
                let unit: FddbUnit = section.range(of: "ml", options: .caseInsensitive) != nil ? .milliliters : .grams
                let serving = detectStandardServing(in: html)
                return FddbImportResult(
                    name: name,
                    carbs: m.carbs,
                    protein: m.protein,
                    fat: m.fat,
                    calories: m.calories,
                    fiber: m.fiber,
                    sugars: m.sugars,
                    mode: .per100(unit: unit),
                    standardServingSize: serving?.size,
                    standardServingUnit: serving?.unit
                )
            }
        }

        // 3) Fallback: parse globally, then try to normalize by portions if a total is implied
        let m = parseMacros(in: html)
        if m.carbs != nil || m.protein != nil || m.fat != nil || m.calories != nil {
            let portions = firstRegexGroup(
                in: html,
                pattern: "(?:für\\s*)?([0-9]+)\\s*Portion(?:en)?",
                options: [.caseInsensitive]
            ).flatMap { decimal(from: $0) }

            if let portions = portions, portions > 1 {
                let normalized = normalizePerPortion(
                    name: name,
                    carbs: m.carbs,
                    protein: m.protein,
                    fat: m.fat,
                    calories: m.calories,
                    fiber: m.fiber,
                    sugars: m.sugars,
                    portions: portions
                )
                let serving = detectStandardServing(in: html)
                return FddbImportResult(
                    name: normalized.name,
                    carbs: normalized.carbs,
                    protein: normalized.protein,
                    fat: normalized.fat,
                    calories: normalized.calories,
                    fiber: normalized.fiber,
                    sugars: normalized.sugars,
                    mode: .perServing,
                    standardServingSize: serving?.size,
                    standardServingUnit: serving?.unit
                )
            } else {
                let serving = detectStandardServing(in: html)
                return FddbImportResult(
                    name: name,
                    carbs: m.carbs,
                    protein: m.protein,
                    fat: m.fat,
                    calories: m.calories,
                    fiber: m.fiber,
                    sugars: m.sugars,
                    mode: .perServing,
                    standardServingSize: serving?.size,
                    standardServingUnit: serving?.unit
                )
            }
        }

        return nil
    }

    // MARK: - Helpers

    /// Normalize totals to per single portion; if `portions` is nil or <= 0, values are returned unchanged.
    private static func normalizePerPortion(
        name: String,
        carbs: Decimal?,
        protein: Decimal?,
        fat: Decimal?,
        calories: Decimal?,
        fiber: Decimal?,
        sugars: Decimal?,
        portions: Decimal?
    ) -> FddbImportResult {
        let divisor: Decimal = (portions ?? 1) > 0 ? (portions ?? 1) : 1
        func perPortion(_ value: Decimal?) -> Decimal? {
            guard let v = value else { return nil }
            return v / divisor
        }
        return FddbImportResult(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            carbs: perPortion(carbs) ?? carbs,
            protein: perPortion(protein) ?? protein,
            fat: perPortion(fat) ?? fat,
            calories: perPortion(calories),
            fiber: perPortion(fiber),
            sugars: perPortion(sugars),
            mode: .perServing,
            standardServingSize: nil,
            standardServingUnit: nil
        )
    }

    /// Try to parse a number/decimal from heterogeneous JSON values or numeric strings (comma or dot decimal)
    private static func decimal(from any: Any?) -> Decimal? {
        switch any {
        case let d as Decimal:
            return d
        case let n as NSNumber:
            return n.decimalValue
        case let s as String:
            let lower = s
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let removedUnits = lower
                .replacingOccurrences(of: " kcal", with: "")
                .replacingOccurrences(of: "kcal", with: "")
                .replacingOccurrences(of: " kj", with: "")
                .replacingOccurrences(of: "kj", with: "")
                .replacingOccurrences(of: " g", with: "")
                .replacingOccurrences(of: "g", with: "")
                .replacingOccurrences(of: " ml", with: "")
                .replacingOccurrences(of: "ml", with: "")
            return Decimal(string: removedUnits)
        default:
            return nil
        }
    }

    /// Extract number of portions from various shapes (e.g., "10" or "für 10 Portionen")
    private static func parsePortions(from any: Any?) -> Decimal? {
        if let n = any as? NSNumber { return n.decimalValue }
        if let s = any as? String {
            if let direct = Decimal(string: s.replacingOccurrences(of: ",", with: ".")) { return direct }
            if let g = firstRegexGroup(in: s, pattern: "([0-9]+)", options: []) { return Decimal(string: g) }
        }
        return nil
    }

    /// Returns the first regex capture group for the given pattern.
    private static func firstRegexGroup(in text: String, pattern: String, options: NSRegularExpression.Options) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 2 else { return nil }
        let groupRange = match.range(at: 1)
        guard let swiftRange = Range(groupRange, in: text) else { return nil }
        return String(text[swiftRange])
    }

    /// Returns the overall match range for the first regex occurrence (not a capture group)
    private static func firstRegexRange(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options
    ) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard let swiftRange = Range(match.range, in: text) else { return nil }
        return swiftRange
    }

    /// Safely slice a window around a given range
    private static func slice(_ text: String, around range: Range<String.Index>, before: Int, after: Int) -> String {
        let start = text.index(range.lowerBound, offsetBy: -before, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: after, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start ..< end])
    }

    /// Parse macros in a constrained HTML snippet using strict unit-bound patterns
    private static func parseMacros(in section: String)
        -> (carbs: Decimal?, protein: Decimal?, fat: Decimal?, calories: Decimal?, fiber: Decimal?, sugars: Decimal?)
    {
        // Units patterns (strict) with word boundaries
        let gramsUnits = "(?:g|gramm|gr)\\b"
        let mlUnits = "(?:ml|milliliter)\\b" // reserved if we ever need volume-based macros

        func captureStrict(labelPattern: String, unitsPattern: String) -> Decimal? {
            let pattern = "(?:\(labelPattern)\\)[^0-9]{0,80}([0-9]+(?:[\\.,][0-9]+)?)\\s*\(unitsPattern)"
            return firstRegexGroup(in: section, pattern: pattern, options: [.caseInsensitive]).flatMap { decimal(from: $0) }
        }

        func captureLoose(labelPattern: String) -> Decimal? {
            // No units, still constrained near the label
            let pattern = "(?:\(labelPattern)\\)[^0-9]{0,80}([0-9]+(?:[\\.,][0-9]+)?)"
            return firstRegexGroup(in: section, pattern: pattern, options: [.caseInsensitive]).flatMap { decimal(from: $0) }
        }

        // Macros in grams
        let carbs = captureStrict(labelPattern: "Kohlenhydrate|carbohydrate(?:s)?", unitsPattern: gramsUnits)
            ?? captureLoose(labelPattern: "Kohlenhydrate|carbohydrate(?:s)?")
        let protein = captureStrict(labelPattern: "Eiweiß|Eiweiss|protein", unitsPattern: gramsUnits)
            ?? captureLoose(labelPattern: "Eiweiß|Eiweiss|protein")
        let fat = captureStrict(labelPattern: "Fett|fat", unitsPattern: gramsUnits)
            ?? captureLoose(labelPattern: "Fett|fat")
        let fiber = captureStrict(labelPattern: "Ballaststoffe|fiber", unitsPattern: gramsUnits)
            ?? captureLoose(labelPattern: "Ballaststoffe|fiber")
        let sugars = captureStrict(labelPattern: "Zucker|sugars?", unitsPattern: gramsUnits)
            ?? captureLoose(labelPattern: "Zucker|sugars?")

        // Calories: prefer explicit kcal, then labeled kcal
        let calories = firstRegexGroup(
            in: section,
            pattern: "([0-9]+(?:[\\.,][0-9]+)?)\\s*(?:kcal|kilokalorien)",
            options: [.caseInsensitive]
        ).flatMap { decimal(from: $0) }
            ?? firstRegexGroup(
                in: section,
                pattern: "(?:Kalorien|Brennwert|Energie)[^0-9]{0,60}([0-9]+(?:[\\.,][0-9]+)?)\\s*(?:kcal|kilokalorien)",
                options: [.caseInsensitive]
            ).flatMap { decimal(from: $0) }

        return (carbs, protein, fat, calories, fiber, sugars)
    }

    /// Extract a likely name from <h1>, og:title, or <title>
    private static func extractName(from html: String) -> String? {
        if let h1 = firstRegexGroup(
            in: html,
            pattern: "<h1[^>]*>(.*?)</h1>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            return h1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let og = firstRegexGroup(
            in: html,
            pattern: "<meta[^>]*property=\\\"og:title\\\"[^>]*content=\\\"(.*?)\\\"",
            options: [.caseInsensitive]
        ) {
            return og.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let title = firstRegexGroup(
            in: html,
            pattern: "<title[^>]*>(.*?)</title>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Detect if the page contains an explicit per-100 block and return its unit (grams/ml)
    private static func detectPer100Unit(in html: String) -> FddbUnit? {
        if firstRegexGroup(in: html, pattern: "((?:pro|je)\\s*100\\s*g|100\\s*g|100g)", options: [.caseInsensitive]) != nil {
            return .grams
        }
        if firstRegexGroup(in: html, pattern: "((?:pro|je)\\s*100\\s*ml|100\\s*ml|100ml)", options: [.caseInsensitive]) != nil {
            return .milliliters
        }
        return nil
    }

    /// Try to detect a clear standard serving size like "1 Portion = 250 ml" or "pro Portion 250 g" (incl. "à/á")
    private static func detectStandardServing(in html: String) -> (size: Decimal, unit: FddbUnit)? {
        // Pattern 1: "1 Portion = 250 ml" or "1 Portion = 250 g"
        if let sizeStr = firstRegexGroup(
            in: html,
            pattern: "1\\s*Portion\\s*=\\s*([0-9]+(?:[\\.,][0-9]+)?)\\s*(g|ml)",
            options: [.caseInsensitive]
        ),
            let size = decimal(from: sizeStr)
        {
            if let unitStr = firstRegexGroup(
                in: html,
                pattern: "1\\s*Portion\\s*=\\s*[0-9]+(?:[\\.,][0-9]+)?\\s*(g|ml)",
                options: [.caseInsensitive]
            ) {
                let unit = unitStr.lowercased().contains("ml") ? FddbUnit.milliliters : FddbUnit.grams
                return (size, unit)
            }
        }
        // Pattern 2: "pro Portion 250 ml/g"
        if let sizeStr = firstRegexGroup(
            in: html,
            pattern: "pro\\s*Portion\\s*([0-9]+(?:[\\.,][0-9]+)?)\\s*(g|ml)",
            options: [.caseInsensitive]
        ),
            let size = decimal(from: sizeStr)
        {
            if let unitStr = firstRegexGroup(
                in: html,
                pattern: "pro\\s*Portion\\s*[0-9]+(?:[\\.,][0-9]+)?\\s*(g|ml)",
                options: [.caseInsensitive]
            ) {
                let unit = unitStr.lowercased().contains("ml") ? FddbUnit.milliliters : FddbUnit.grams
                return (size, unit)
            }
        }
        // Pattern 3: "pro Portion à/á 250 g/ml"
        if let sizeStr = firstRegexGroup(
            in: html,
            pattern: "pro\\s*Portion\\s*(?:à|á)\\s*([0-9]+(?:[\\.,][0-9]+)?)\\s*(g|ml)",
            options: [.caseInsensitive]
        ),
            let size = decimal(from: sizeStr)
        {
            if let unitStr = firstRegexGroup(
                in: html,
                pattern: "pro\\s*Portion\\s*(?:à|á)\\s*[0-9]+(?:[\\.,][0-9]+)?\\s*(g|ml)",
                options: [.caseInsensitive]
            ) {
                let unit = unitStr.lowercased().contains("ml") ? FddbUnit.milliliters : FddbUnit.grams
                return (size, unit)
            }
        }
        return nil
    }

    /// Extract JSON-LD blocks (<script type="application/ld+json">...</script>)
    private static func extractJSONLD(html: String) -> [[String: Any]]? {
        let pattern = "<script[^>]*type=\\\"application/ld\\+json\\\"[^>]*>([\\s\\S]*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        var results: [[String: Any]] = []
        for match in matches {
            guard match.numberOfRanges >= 2, let r = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[r])
            guard let data = jsonString.data(using: .utf8) else { continue }
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                results.append(contentsOf: arr)
            } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                results.append(obj)
            }
        }
        return results.isEmpty ? nil : results
    }

    /// Extract embedded JSON objects from common variables like __INITIAL_STATE__ = {...};
    private static func extractEmbeddedJSON(html: String) -> [[String: Any]]? {
        let patterns = [
            "__INITIAL_STATE__\\s*=\\s*({[\\s\\S]*?})\\s*;",
            "window\\.\\w+\\s*=\\s*({[\\s\\S]*?})\\s*;",
            "var\\s+\\w+\\s*=\\s*({[\\s\\S]*?})\\s*;"
        ]
        var results: [[String: Any]] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex ..< html.endIndex, in: html)
            let matches = regex.matches(in: html, options: [], range: range)
            for m in matches {
                guard m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) else { continue }
                let json = String(html[r])
                guard let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                results.append(obj)
            }
        }
        return results.isEmpty ? nil : results
    }
}
