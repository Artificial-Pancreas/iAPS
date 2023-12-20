import Foundation
import SwiftUI
import Swinject

extension Stat {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Published var highLimit: Decimal = 10 / 0.0555
        @Published var lowLimit: Decimal = 4 / 0.0555
        @Published var overrideUnit: Bool = false
        @Published var layingChart: Bool = false
        @Published var units: GlucoseUnits = .mmolL
        @Published var preview: Bool = false
        @Published var readings: [Readings] = []

        override func subscribe() {
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            layingChart = settingsManager.settings.oneDimensionalGraph
        }
    }
}
