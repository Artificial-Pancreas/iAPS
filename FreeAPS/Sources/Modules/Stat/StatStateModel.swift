import Foundation
import SwiftUI
import Swinject

extension Stat {
    final class StateModel: BaseStateModel<Provider> {
        @Published var highLimit: Decimal = 10 / 0.0555
        @Published var lowLimit: Decimal = 4 / 0.0555
        @Published var overrideUnit: Bool = false
        @Published var layingChart: Bool = false
        @Published var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            let settings = await settingsManager.settings
            highLimit = settings.high
            lowLimit = settings.low
            units = settings.units
            overrideUnit = settings.overrideHbA1cUnit
            layingChart = settings.oneDimensionalGraph
        }
    }
}
