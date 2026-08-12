import Foundation
import NightscoutKit

struct BloodGlucose: JSON, Identifiable, Hashable, Codable, Sendable {
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
        case uncalibrated
        case noise
        case glucose
        case type
        case activationDate
        case sessionStartDate
        case transmitterID
        case device
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)

        guard let value = Self.decodeValue(from: container, forKey: .glucose)
            ?? Self.decodeValue(from: container, forKey: .sgv)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.glucose,
                .init(codingPath: container.codingPath, debugDescription: "neither `glucose` nor `sgv` present")
            )
        }
        glucose = value

        direction = try container.decodeIfPresent(Direction.self, forKey: .direction)
        date = try container.decode(Decimal.self, forKey: .date)
        dateString = try container.decode(Date.self, forKey: .dateString)
        uncalibrated = try container.decodeIfPresent(Decimal.self, forKey: .uncalibrated) ?? Decimal(value)
        noise = try container.decodeIfPresent(Int.self, forKey: .noise)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        activationDate = try container.decodeIfPresent(Date.self, forKey: .activationDate)
        sessionStartDate = try container.decodeIfPresent(Date.self, forKey: .sessionStartDate)
        transmitterID = try container.decodeIfPresent(String.self, forKey: .transmitterID)
        device = try container.decodeIfPresent(String.self, forKey: .device)
    }

    private static func decodeValue(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let int = try? container.decodeIfPresent(Int.self, forKey: key) { return int }
        if let double = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(double) }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(glucose, forKey: .glucose)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encode(date, forKey: .date)
        try container.encode(dateString, forKey: .dateString)
        try container.encode(uncalibrated, forKey: .uncalibrated)
        try container.encodeIfPresent(noise, forKey: .noise)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(activationDate, forKey: .activationDate)
        try container.encodeIfPresent(sessionStartDate, forKey: .sessionStartDate)
        try container.encodeIfPresent(transmitterID, forKey: .transmitterID)
        try container.encodeIfPresent(device, forKey: .device)
    }

    init(
        _id: String = UUID().uuidString,
        glucose: Int,
        direction: Direction? = nil,
        date: Decimal,
        dateString: Date,
        uncalibrated: Decimal? = nil,
        noise: Int? = nil,
        type: String? = nil,
        activationDate: Date? = nil,
        sessionStartDate: Date? = nil,
        transmitterID: String? = nil,
        device: String? = nil,
    ) {
        self._id = _id
        self.glucose = glucose
        self.direction = direction
        self.date = date
        self.dateString = dateString
        self.uncalibrated = uncalibrated ?? Decimal(glucose)
        self.noise = noise
        self.type = type
        self.activationDate = activationDate
        self.sessionStartDate = sessionStartDate
        self.transmitterID = transmitterID
        self.device = device
    }

    var _id = UUID().uuidString
    var id: String {
        _id
    }

    /// one glucose value of this reading, mg/dL.
    /// different streams in AppCoordinator contain different blood glucose values (raw vs smoothed)
    var glucose: Int
    var direction: Direction?
    let date: Decimal
    let dateString: Date
    /// raw value before calibration was applied
    let uncalibrated: Decimal
    let noise: Int?
    let type: String?
    // TODO: unused, always nil?
    var activationDate: Date? = nil
    var sessionStartDate: Date? = nil
    // TODO: unused, always nil?
    var transmitterID: String? = nil
    var device: String? = nil

    var isStateValid: Bool { glucose >= 39 && noise ?? 1 != 4 }

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
            Double(glucose)
        }
        set {
            glucose = Int(newValue)
        }
    }
}

extension BloodGlucose {
    static func from(nightscout entry: GlucoseEntry) -> BloodGlucose? {
        guard let id = entry.id else { return nil }
        let direction = (entry.trend?.direction).flatMap { BloodGlucose.Direction(rawValue: $0) }
        let glucose = Int(entry.glucose.rounded())
        let type: String?
        switch entry.glucoseType {
        case .sensor: type = "sgv"
        case .meter: type = "mbg"
        }
        return BloodGlucose(
            _id: id,
            glucose: glucose,
            direction: direction,
            date: Decimal(entry.date.timeIntervalSince1970 * 1000),
            dateString: entry.date,
            noise: nil,
            type: type,
            activationDate: nil,
            sessionStartDate: nil,
            transmitterID: nil,
            device: entry.device,
        )
    }

    var toNightscoutEntry: GlucoseEntry? {
        let glucose = Double(self.glucose)

        let glucoseType: GlucoseEntry.GlucoseType
        let isCalibration: Bool
        if type == GlucoseType.manual.rawValue {
            glucoseType = .meter
            isCalibration = false
        } else if type == GlucoseType.sgv.rawValue {
            glucoseType = .sensor
            isCalibration = false
        } else if type == GlucoseType.cal.rawValue {
            glucoseType = .meter
            isCalibration = true
        } else {
            return nil
        }

        let trend: GlucoseEntry.GlucoseTrend? = direction.flatMap { Self.trendFromDirection($0.rawValue) }

        return GlucoseEntry(
            glucose: glucose,
            date: dateString,
            device: device,
            glucoseType: glucoseType,
            trend: trend,
            changeRate: nil,
            isCalibration: isCalibration,
            condition: nil,
            id: id
        )
    }

    private static func trendFromDirection(_ direction: String?) -> GlucoseEntry.GlucoseTrend? {
        for trend in GlucoseEntry.GlucoseTrend.allCases {
            if direction == trend.direction {
                return trend
            }
        }
        return nil
    }
}

extension BloodGlucose.Direction {
    var symbol: String {
        switch self {
        case .tripleUp:
            return "↑↑↑"
        case .doubleUp:
            return "↑↑"
        case .singleUp:
            return "↑"
        case .fortyFiveUp:
            return "↗︎"
        case .flat:
            return "→"
        case .fortyFiveDown:
            return "↘︎"
        case .singleDown:
            return "↓"
        case .doubleDown:
            return "↓↓"
        case .tripleDown:
            return "↓↓↓"
        case .none:
            return "↔︎"
        case .notComputable:
            return "↔︎"
        case .rateOutOfRange:
            return "↔︎"
        }
    }

    var sfSymbol: String {
        switch self {
        case .tripleUp:
            return "chevron.up.circle.fill"
        case .doubleUp:
            return "chevron.up.circle.fill"
        case .singleUp:
            return "arrow.up.circle.fill"
        case .fortyFiveUp:
            return "arrow.up.right.circle.fill"
        case .flat:
            return "arrow.right.circle.fill"
        case .fortyFiveDown:
            return "arrow.down.right.circle.fill"
        case .singleDown:
            return "arrow.down.circle.fill"
        case .doubleDown:
            return "chevron.down.circle.fill"
        case .tripleDown:
            return "chevron.down.circle.fill"
        case .none,
             .notComputable,
             .rateOutOfRange:
            return "minus.circle.fill"
        }
    }
}
