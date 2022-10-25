import Foundation

struct DailyStats: JSON, Equatable {
    var date: Date
    var Pump: String
    var CGM: String
    var TIR_Percentage: Decimal
    var Hypoglucemias_Percentage: Decimal
    var Hyperglucemias_Percentage: Decimal
    var BG_daily_Average: Decimal
    var TDD: Decimal
    var Carbs_24h: Decimal
    var Algorithm: String
    var AdjustmentFactor: Decimal
    var insulinType: String
    var peakActivityTime: Decimal
    var FAX_Build_Version: String
    var FAX_Build_Number: String
    var FAX_Build_Date: Date
    var id: String

    init(
        date: Date,
        Pump: String,
        CGM: String,
        TIR_Percentage: Decimal,
        Hypoglucemias_Percentage: Decimal,
        Hyperglucemias_Percentage: Decimal,
        BG_daily_Average: Decimal,
        TDD: Decimal,
        Carbs_24h: Decimal,
        Algorithm: String,
        AdjustmentFactor: Decimal,
        insulinType: String,
        peakActivityTime: Decimal,
        FAX_Build_Version: String,
        FAX_Build_Number: String,
        FAX_Build_Date: Date,
        id: String
    ) {
        self.date = date
        self.Pump = Pump
        self.CGM = CGM
        self.TIR_Percentage = TIR_Percentage
        self.Hypoglucemias_Percentage = Hypoglucemias_Percentage
        self.Hyperglucemias_Percentage = Hyperglucemias_Percentage
        self.BG_daily_Average = BG_daily_Average
        self.TDD = TDD
        self.Carbs_24h = Carbs_24h
        self.Algorithm = Algorithm
        self.AdjustmentFactor = AdjustmentFactor
        self.insulinType = insulinType
        self.peakActivityTime = peakActivityTime
        self.FAX_Build_Version = FAX_Build_Version
        self.FAX_Build_Number = FAX_Build_Number
        self.FAX_Build_Date = FAX_Build_Date
        self.id = id
    }
}

extension DailyStats {
    private enum CodingKeys: String, CodingKey {
        case date
        case Pump
        case CGM
        case TIR_Percentage
        case Hypoglucemias_Percentage
        case Hyperglucemias_Percentage
        case BG_daily_Average
        case TDD
        case Carbs_24h
        case Algorithm
        case AdjustmentFactor
        case insulinType
        case peakActivityTime
        case FAX_Build_Version
        case FAX_Build_Number
        case FAX_Build_Date
        case id
    }
}
