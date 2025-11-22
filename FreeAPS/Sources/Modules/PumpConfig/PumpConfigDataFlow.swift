import Combine
import LoopKit
import LoopKitUI

enum PumpConfig {
    enum Config {}

    struct PumpInitialSettings {
        let maxBolusUnits: Double
        let maxBasalRateUnitsPerHour: Double
        let basalSchedule: BasalRateSchedule

        static let `default` = PumpInitialSettings(
            maxBolusUnits: 10,
            maxBasalRateUnitsPerHour: 4,
            basalSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        )
    }
}

struct PumpDisplayState {
    let name: String
    let image: UIImage?
}

protocol PumpConfigProvider: Provider {
    func pumpSettings() -> PumpSettings
    func basalProfile() -> [BasalProfileEntry]
}
