import Foundation

struct DailyStats: JSON, Equatable {
    var date: Date
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
    var BG_daily_Average_mg_dl: Decimal
    var HbA1c: String
    var id: String

    init(
        date: Date,
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
        BG_daily_Average_mg_dl: Decimal,
        HbA1c: String,
        id: String
    ) {
        self.date = date
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
        self.BG_daily_Average_mg_dl = BG_daily_Average_mg_dl
        self.HbA1c = HbA1c
        self.id = id
    }
}

extension DailyStats {
    private enum CodingKeys: String, CodingKey {
        case date
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
        case BG_daily_Average_mg_dl
        case HbA1c
        case id
    }
}
