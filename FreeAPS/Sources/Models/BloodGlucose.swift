import Foundation

struct BloodGlucose: JSON, Identifiable, Hashable, Codable {
    enum Direction: String, JSON {
        case tripleUp = "TripleUp"
        case doubleUp = "DoubleUp"
        case singleUp = "SingleUp"
        case fortyFiveUp = "FortyFiveUp"
        case flat = "Flat"
        case fortyFiveDown = "FortyFiveDown"
        case singleDown = "SingleDown"
        case doubleDown = "DoubleDown"
        case tripleDown = "TripleDown"
        case none = "NONE"
        case notComputable = "NOT COMPUTABLE"
        case rateOutOfRange = "RATE OUT OF RANGE"
    }

    enum CodingKeys: String, CodingKey {
        case _id
        case sgv
        case direction
        case date
        case dateString
        case unfiltered
        case filtered
        case noise
        case glucose
        case type
        case activationDate
        case sessionStartDate
        case transmitterID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)

        do {
            sgv = try container.decode(Int.self, forKey: .sgv)
        } catch {
            // The nightscout API returns a double instead of an int
            sgv = Int(try container.decode(Double.self, forKey: .sgv))
        }

        direction = try container.decodeIfPresent(Direction.self, forKey: .direction)
        date = try container.decode(Decimal.self, forKey: .date)
        dateString = try container.decode(Date.self, forKey: .dateString)
        unfiltered = try container.decodeIfPresent(Decimal.self, forKey: .unfiltered)
        filtered = try container.decodeIfPresent(Decimal.self, forKey: .filtered)
        noise = try container.decodeIfPresent(Int.self, forKey: .noise)
        glucose = try container.decodeIfPresent(Int.self, forKey: .glucose)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        activationDate = try container.decodeIfPresent(Date.self, forKey: .activationDate)
        sessionStartDate = try container.decodeIfPresent(Date.self, forKey: .sessionStartDate)
        transmitterID = try container.decodeIfPresent(String.self, forKey: .transmitterID)
    }

    init(
        _id: String = UUID().uuidString,
        sgv: Int? = nil,
        direction: Direction? = nil,
        date: Decimal,
        dateString: Date,
        unfiltered: Decimal? = nil,
        filtered: Decimal? = nil,
        noise: Int? = nil,
        glucose: Int? = nil,
        type: String? = nil,
        activationDate: Date? = nil,
        sessionStartDate: Date? = nil,
        transmitterID: String? = nil
    ) {
        self._id = _id
        self.sgv = sgv
        self.direction = direction
        self.date = date
        self.dateString = dateString
        self.unfiltered = unfiltered
        self.filtered = filtered
        self.noise = noise
        self.glucose = glucose
        self.type = type
        self.activationDate = activationDate
        self.sessionStartDate = sessionStartDate
        self.transmitterID = transmitterID
    }

    var _id = UUID().uuidString
    var id: String {
        _id
    }

    var sgv: Int?
    var direction: Direction?
    let date: Decimal
    let dateString: Date
    let unfiltered: Decimal?
    let filtered: Decimal?
    let noise: Int?
    var glucose: Int?
    let type: String?
    var activationDate: Date? = nil
    var sessionStartDate: Date? = nil
    var transmitterID: String? = nil

    var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }

    static func == (lhs: BloodGlucose, rhs: BloodGlucose) -> Bool {
        lhs.dateString == rhs.dateString
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateString)
    }
}

enum GlucoseUnits: String, JSON, Equatable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    static let exchangeRate: Decimal = 0.0555
}

extension Int {
    var asMmolL: Decimal {
        Decimal(self) * GlucoseUnits.exchangeRate
    }
}

extension Decimal {
    var asMmolL: Decimal {
        self * GlucoseUnits.exchangeRate
    }

    var asMgdL: Decimal {
        self / GlucoseUnits.exchangeRate
    }

    func rounded(to scale: Int, roundingMode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, roundingMode)
        return result
    }
}

extension Double {
    var asMmolL: Decimal {
        Decimal(self) * GlucoseUnits.exchangeRate
    }

    var asMgdL: Decimal {
        Decimal(self) / GlucoseUnits.exchangeRate
    }
}

extension BloodGlucose: SavitzkyGolaySmoothable {
    var value: Double {
        get {
            Double(glucose ?? 0)
        }
        set {
            glucose = Int(newValue)
            sgv = Int(newValue)
        }
    }
}
