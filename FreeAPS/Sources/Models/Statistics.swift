import Foundation

struct Statistics: JSON, Equatable {
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
    var GlucoseStorage_Days: Decimal
    var Statistics: Stats

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
        GlucoseStorage_Days: Decimal,
        Statistics: Stats
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
        self.GlucoseStorage_Days = GlucoseStorage_Days
        self.Statistics = Statistics
    }

    static func == (lhs: Statistics, rhs: Statistics) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }
}

extension Statistics {
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
        case GlucoseStorage_Days
        case Statistics
    }
}

struct LoopCycles: JSON, Equatable {
    var loops: Int
    var errors: Int
    var success_rate: Decimal
    var avg_interval: Decimal
    var median_interval: Decimal
    var min_interval: Decimal
    var max_interval: Decimal
    var avg_duration: Decimal
    var median_duration: Decimal
    var min_duration: Decimal
    var max_duration: Decimal
}

struct Averages: JSON, Equatable {
    var Average: [Average]
    var Median: [Median]
}

struct Average: JSON, Equatable {
    var oneDay_mmol: Decimal
    var oneDay: Decimal
    var sevenDays_mmol: Decimal
    var sevenDays: Decimal
    var thirtyDays_mmol: Decimal
    var thirtyDays: Decimal
    var ninetyDays_mmol: Decimal
    var ninetyDays: Decimal
    var totalDays_mmol: Decimal
    var totalDays: Decimal
}

struct Median: JSON, Equatable {
    var oneDay_mmol: Decimal
    var oneDay: Decimal
    var sevenDays_mmol: Decimal
    var sevenDays: Decimal
    var thirtyDays_mmol: Decimal
    var thirtyDays: Decimal
    var ninetyDays_mmol: Decimal
    var ninetyDays: Decimal
    var totalDays_mmol: Decimal
    var totalDays: Decimal
}

struct Hbs: JSON, Equatable {
    var oneDay_mmolMol: Decimal
    var oneDay: Decimal
    var sevenDays_mmolMol: Decimal
    var sevenDays: Decimal
    var thirtyDays_mmolMol: Decimal
    var thirtyDays: Decimal
    var ninetyDays_mmolMol: Decimal
    var ninetyDays: Decimal
    var totalDays_mmolMol: Decimal
    var totalDays: Decimal
}

struct TIRs: JSON, Equatable {
    var TIR: [TIR]
    var Hypos: [Hypos]
    var Hypers: [Hypers]
}

struct TIR: JSON, Equatable {
    var oneDay: Decimal
    var sevenDays: Decimal
    var thirtyDays: Decimal
    var ninetyDays: Decimal
    var totalDays: Decimal
}

struct Hypos: JSON, Equatable {
    var oneDay: Decimal
    var sevenDays: Decimal
    var thirtyDays: Decimal
    var ninetyDays: Decimal
    var totalDays: Decimal
}

struct Hypers: JSON, Equatable {
    var oneDay: Decimal
    var sevenDays: Decimal
    var thirtyDays: Decimal
    var ninetyDays: Decimal
    var totalDays: Decimal
}

struct Stats: JSON, Equatable {
    var Distribution: [TIRs]
    var Glucose: [Averages]
    var HbA1c: [Hbs]
    var LoopCycles: [LoopCycles]
}

extension LoopCycles {
    private enum CodingKeys: String, CodingKey {
        case loops
        case errors
        case success_rate
        case avg_interval
        case median_interval
        case min_interval
        case max_interval
        case avg_duration
        case median_duration
        case min_duration
        case max_duration
    }
}

extension Averages {
    private enum CodingKeys: String, CodingKey {
        case Average
        case Median
    }
}

extension Median {
    private enum CodingKeys: String, CodingKey {
        case oneDay_mmol
        case oneDay
        case sevenDays_mmol
        case sevenDays
        case thirtyDays_mmol
        case thirtyDays
        case ninetyDays_mmol
        case ninetyDays
        case totalDays_mmol
        case totalDays
    }
}

extension Hbs {
    private enum CodingKeys: String, CodingKey {
        case oneDay_mmolMol
        case oneDay
        case sevenDays_mmolMol
        case sevenDays
        case thirtyDays_mmolMol
        case thirtyDays
        case ninetyDays_mmolMol
        case ninetyDays
        case totalDays_mmolMol
        case totalDays
    }
}

extension TIRs {
    private enum CodingKeys: String, CodingKey {
        case TIR
        case Hypos
        case Hypers
    }
}

extension Hypos {
    private enum CodingKeys: String, CodingKey {
        case oneDay
        case sevenDays
        case thirtyDays
        case ninetyDays
        case totalDays
    }
}

extension Hypers {
    private enum CodingKeys: String, CodingKey {
        case oneDay
        case sevenDays
        case thirtyDays
        case ninetyDays
        case totalDays
    }
}

extension Stats {
    private enum CodingKeys: String, CodingKey {
        case Distribution
        case Glucose
        case HbA1c
        case LoopCycles
    }
}
