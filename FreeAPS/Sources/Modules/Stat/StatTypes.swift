import Foundation
import SwiftUI

// MARK: - View Type Enums

enum StatisticViewType: String, CaseIterable, Identifiable {
    case overview
    case glucose
    case looping
    case insulin
    case meals

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview: return NSLocalizedString("Overview", comment: "")
        case .glucose: return NSLocalizedString("Glucose", comment: "")
        case .insulin: return NSLocalizedString("Insulin", comment: "")
        case .looping: return NSLocalizedString("Looping", comment: "")
        case .meals: return NSLocalizedString("Meals", comment: "")
        }
    }
}

// MARK: - Time Intervals

enum StatsTimeIntervalWithToday: String, CaseIterable, Identifiable {
    case today
    case day = "D"
    case week = "W"
    case month = "M"
    case total = "3 M"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .today: return NSLocalizedString("Today", comment: "")
        case .day: return NSLocalizedString("D", comment: "Abbreviation for day")
        case .week: return NSLocalizedString("W", comment: "Abbreviation for week")
        case .month: return NSLocalizedString("M", comment: "Abbreviation for month")
        case .total: return NSLocalizedString("3 M", comment: "Abbreviation for three months")
        }
    }
}

extension StatsTimeIntervalWithToday {
    /// Maps to StatsTimeInterval for chart utilities — .today behaves like .day
    var asChartInterval: StatsTimeInterval {
        switch self {
        case .day,
             .today: return .day
        case .week: return .week
        case .month: return .month
        case .total: return .total
        }
    }

    var isHourly: Bool { self == .today || self == .day }
}

enum StatsTimeInterval: String, CaseIterable, Identifiable {
    case day = "D"
    case week = "W"
    case month = "M"
    case total = "3 M"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .day: return NSLocalizedString("D", comment: "Abbreviation for day")
        case .week: return NSLocalizedString("W", comment: "Abbreviation for week")
        case .month: return NSLocalizedString("M", comment: "Abbreviation for month")
        case .total: return NSLocalizedString("3 M", comment: "Abbreviation for three months")
        }
    }
}

// MARK: - Chart Type Enums

enum GlucoseChartType: String, CaseIterable {
    case sectorAndMetrics = "Overview"
    case percentileByTime = "Percentile"
    case distribution = "Distribution"

    var displayName: String {
        switch self {
        case .sectorAndMetrics: return NSLocalizedString("Overview", comment: "")
        case .percentileByTime: return NSLocalizedString("Percentile", comment: "")
        case .distribution: return NSLocalizedString("Distribution", comment: "")
        }
    }
}

enum InsulinChartType: String, CaseIterable {
    case totalDailyDose = "Total Daily Dose"
    case bolusDistribution = "Bolus Distribution"

    var displayName: String {
        switch self {
        case .totalDailyDose: return NSLocalizedString("Total Daily Dose", comment: "")
        case .bolusDistribution: return NSLocalizedString("Bolus Distribution", comment: "")
        }
    }
}

enum LoopingChartType: String, CaseIterable {
    case loopingPerformance = "Looping Performance"

    var displayName: String {
        NSLocalizedString("Looping Performance", comment: "")
    }
}

enum MealChartType: String, CaseIterable {
    case totalMeals = "Total Meals"

    var displayName: String {
        NSLocalizedString("Total Meals", comment: "")
    }
}

// MARK: - Data Structs

struct TDDStats: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
}

struct BolusStats: Identifiable {
    let id = UUID()
    let date: Date
    let manualBolus: Double
    let smb: Double
    let external: Double
}

struct MealStats: Identifiable {
    let id = UUID()
    let date: Date
    let carbs: Double
    let fat: Double
    let protein: Double
}

struct HourlyStats: Equatable {
    let hour: Int
    let median: Double
    let percentile25: Double
    let percentile75: Double
    let percentile10: Double
    let percentile90: Double
}

struct AGPSlot: Identifiable {
    let id: Int // minute of day (0, 30, 60, ...)
    let date: Date // reference date for charting
    let p10: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p90: Double
}

struct LoopStatsProcessedData: Identifiable {
    var id = UUID()
    let category: LoopStatsDataType
    let count: Int
    let percentage: Double
    let successPercentage: Double
    let medianDuration: Double
    let medianInterval: Double
    let totalDays: Int
}

enum LoopStatsDataType: String {
    case successfulLoop
    case glucoseCount

    var displayName: String {
        switch self {
        case .successfulLoop: return NSLocalizedString("Successful Loops", comment: "")
        case .glucoseCount: return NSLocalizedString("Glucose Count", comment: "")
        }
    }
}

struct LoopStatsByPeriod: Identifiable {
    let period: Date
    let successful: Int
    let failed: Int
    let medianDuration: Double
    let glucoseCount: Int
    var total: Int { successful + failed }
    var successPercentage: Double { total > 0 ? Double(successful) / Double(total) * 100 : 0 }
    var id: Date { period }
}

struct GlucoseDistributionSlot: Identifiable {
    let id: Date // calendar day
    let date: Date
    let veryLow: Double // <54 mg/dL (%)
    let low: Double // 54–70 mg/dL (%)
    let inRange: Double // 70–180 mg/dL (%)
    let high: Double // 180–250 mg/dL (%)
    let veryHigh: Double // >250 mg/dL (%)
    let totalReadings: Int
}
