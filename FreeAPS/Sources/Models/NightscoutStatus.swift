import Foundation

struct NightscoutStatus: JSON {
    let device: String
    let openaps: OpenAPSStatus
    let pump: NSPumpStatus
    let preferences: Preferences
    let uploader: Uploader
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
    let status: PumpStatus?
}

struct Uploader: JSON {
    let batteryVoltage: Decimal?
    let battery: Int
}
