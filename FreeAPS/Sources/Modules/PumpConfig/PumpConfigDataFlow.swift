import Combine
import LoopKit
import LoopKitUI

enum PumpConfig {
    enum Config {}

    enum PumpType: Equatable {
        case minimed
        case omnipod
    }

    struct PumpInitialSettings {
        let maxBolusUnits: Double
        let maxBasalRateUnitsPerHour: Double
        let basalSchedule: BasalRateSchedule

        static let `default` = PumpInitialSettings(
            maxBolusUnits: 10,
            maxBasalRateUnitsPerHour: 2,
            basalSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        )
    }
}

protocol PumpConfigProvider: Provider {
    func setPumpManager(_: PumpManagerUI)
}
