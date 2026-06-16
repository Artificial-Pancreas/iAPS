import Foundation

struct NightscoutStatus: JSON {
    let device: String
    let openaps: OpenAPSStatus?
    let pump: NSPumpStatus?
    let uploader: Uploader?
    let createdAt: Date
}

struct OpenAPSStatus: JSON {
    let iob: IOBEntry?
    let suggested: Suggestion?
    let enacted: Suggestion?
    let version: String
}

struct NSPumpStatus: JSON {
    let clock: Date
    let battery: Battery?
    let reservoir: Decimal?
    let status: NSPumpStatusDetails?
}

struct NSPumpStatusDetails: JSON, Equatable {
    let status: NSStatusType
    let bolusing: Bool
    let suspended: Bool
    var timestamp: Date?
}

enum NSStatusType: String, JSON {
    case normal
    case suspended
    case bolusing
}

struct Uploader: JSON {
    let batteryVoltage: Decimal?
    let battery: Int
}

struct NightscoutTimevalue: JSON, Equatable {
    let time: String
    let value: Decimal
    let timeAsSeconds: Int?
}

struct ScheduledNightscoutProfile: JSON, Equatable {
    let dia: Decimal
    let carbs_hr: Int
    let delay: Decimal
    let timezone: String
    let target_low: [NightscoutTimevalue]
    let target_high: [NightscoutTimevalue]
    let sens: [NightscoutTimevalue]
    let basal: [NightscoutTimevalue]
    let carbratio: [NightscoutTimevalue]
    let units: String
}

struct NightscoutProfileStore: JSON {
    let defaultProfile: String
    let startDate: Date
    let mills: Int
    let units: String
    let enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    let profile: String?
}
