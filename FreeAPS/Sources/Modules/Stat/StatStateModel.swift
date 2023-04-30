import Foundation
import SwiftUI
import Swinject

extension Stat {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Published var highLimit: Decimal?
        @Published var lowLimit: Decimal?
        @Published var overrideUnit: Bool?

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            highLimit = settingsManager.settings.highGlucose
            lowLimit = settingsManager.settings.lowGlucose
            units = settingsManager.settings.units
            overrideUnit = settingsManager.preferences.overrideHbA1cUnit
        }
    }
}
