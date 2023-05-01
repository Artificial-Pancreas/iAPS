import Foundation
import SwiftUI
import Swinject

extension Stat {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Published var highLimit: Decimal?
        @Published var lowLimit: Decimal?
        @Published var overrideUnit: Bool?
        @Published var layingChart: Bool?

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            layingChart = settingsManager.settings.oneDimensionalGraph
        }
    }
}
