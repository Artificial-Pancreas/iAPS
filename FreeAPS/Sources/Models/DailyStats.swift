import Foundation

struct DailyStats: JSON, Equatable {
    var createdAt: Date
    var iPhone: String
    var iOS: String
    var Build_Version: String
    var Build_Number: String
    var Branch: String
    var Build_Date: Date
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
    var LoopStats: [LoopCycles]

    init(
        createdAt: Date,
        iPhone: String,
        iOS: String,
        Build_Version: String,
        Build_Number: String,
        Branch: String,
        Build_Date: Date,
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
        HbA1c: String,
        LoopStats: [LoopCycles]
    ) {
        self.createdAt = createdAt
        self.iPhone = iPhone
        self.iOS = iOS
        self.Build_Version = Build_Version
        self.Build_Number = Build_Number
        self.Branch = Branch
        self.Build_Date = Build_Date
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
        self.LoopStats = LoopStats
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
        case iPhone
        case iOS
        case Build_Version
        case Build_Number
        case Branch
        case Build_Date
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
        case LoopStats
    }
}

struct LoopCycles: JSON, Equatable {
    var success_perc: Int
    var loops: Int
    var errors: Int
    var median_interval: String
    var avg_interval: String
    var max_interval: String
    var min_interval: String
    var median_loop: String
    var avg_loop: String
    var max_loop: String
    var min_loop: String
}

extension LoopCycles {
    private enum CodingKeys: String, CodingKey {
        case success_perc
        case loops
        case errors
        case median_interval
        case avg_interval
        case max_interval
        case min_interval
        case median_loop
        case avg_loop
        case max_loop
        case min_loop
    }
}
