import SwiftUI

extension FPUConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var individualAdjustmentFactor: Decimal = 0
        @Published var timeCap: Decimal = 0
        @Published var minuteInterval: Decimal = 0
        @Published var delay: Decimal = 0

        override func subscribe() {
            subscribeSetting(\.timeCap, on: $timeCap.map(Int.init), initial: {
                let value = max(min($0, 12), 3)
                timeCap = Decimal(value)
            }, map: {
                $0
            })

            subscribeSetting(\.minuteInterval, on: $minuteInterval.map(Int.init), initial: {
                let value = max(min($0, 60), 10)
                minuteInterval = Decimal(value)
            }, map: {
                $0
            })

            subscribeSetting(\.delay, on: $delay.map(Int.init), initial: {
                let value = max(min($0, 120), 10)
                delay = Decimal(value)
            }, map: {
                $0
            })

            subscribeSetting(\.individualAdjustmentFactor, on: $individualAdjustmentFactor, initial: {
                let value = max(min($0, 1.2), 0.1)
                individualAdjustmentFactor = value
            }, map: {
                $0
            })
        }
    }
}
