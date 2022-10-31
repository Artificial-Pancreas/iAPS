import Foundation

struct DailyStats: JSON, Equatable {
    var createdAt: Date
    var FAX_Build_Version: String
    var FAX_Build_Number: String
    var FAX_Branch: String
    var FAX_Build_Date: Date
    var Algorithm: String
    var AdjustmentFactor: Decimal
    var Pump: String
    var CGM: String
    var insulinType: String
    var peakActivityTime: Decimal
    var TDD: Decimal
    var Carbs_24h: Decimal
    var TIR: String
    var BG_Average: String
    var HbA1c: String

    init(
        createdAt: Date,
        FAX_Build_Version: String,
        FAX_Build_Number: String,
        FAX_Branch: String,
        FAX_Build_Date: Date,
        Algorithm: String,
        AdjustmentFactor: Decimal,
        Pump: String,
        CGM: String,
        insulinType: String,
        peakActivityTime: Decimal,
        TDD: Decimal,
        Carbs_24h: Decimal,
        TIR: String,
        BG_Average: String,
        HbA1c: String
    ) {
        self.createdAt = createdAt
        self.FAX_Build_Version = FAX_Build_Version
        self.FAX_Build_Number = FAX_Build_Number
        self.FAX_Branch = FAX_Branch
        self.FAX_Build_Date = FAX_Build_Date
        self.Algorithm = Algorithm
        self.AdjustmentFactor = AdjustmentFactor
        self.Pump = Pump
        self.CGM = CGM
        self.insulinType = insulinType
        self.peakActivityTime = peakActivityTime
        self.TDD = TDD
        self.Carbs_24h = Carbs_24h
        self.TIR = TIR
        self.BG_Average = BG_Average
        self.HbA1c = HbA1c
    }

    static func == (lhs: DailyStats, rhs: DailyStats) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }
}

extension DailyStats {
    private enum CodingKeys: String, CodingKey {
        case createdAt
        case FAX_Build_Version
        case FAX_Build_Number
        case FAX_Branch
        case FAX_Build_Date
        case Algorithm
        case AdjustmentFactor
        case Pump
        case CGM
        case insulinType
        case peakActivityTime
        case TDD
        case Carbs_24h
        case TIR
        case BG_Average
        case HbA1c
    }
}
