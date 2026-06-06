import SwiftUI

extension FPUConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var individualAdjustmentFactor: Decimal = 0
        @Published var timeCap: Decimal = 0
        @Published var minuteInterval: Decimal = 0
        @Published var delay: Decimal = 0

        override func subscribe() async {
            // TODO: these values are clamped on read, but not on write

            subscribeSetting(\.timeCap, on: $timeCap.map(Int.init)) {
                let value = max(min($0, 12), 3)
                self.timeCap = Decimal(value)
            }

            subscribeSetting(\.minuteInterval, on: $minuteInterval.map(Int.init)) {
                let value = max(min($0, 60), 10)
                self.minuteInterval = Decimal(value)
            }

            subscribeSetting(\.delay, on: $delay.map(Int.init)) {
                let value = max(min($0, 120), 10)
                self.delay = Decimal(value)
            }

            subscribeSetting(\.individualAdjustmentFactor, on: $individualAdjustmentFactor) {
                let value = max(min($0, 1.2), 0.1)
                self.individualAdjustmentFactor = value
            }
        }
    }
}
