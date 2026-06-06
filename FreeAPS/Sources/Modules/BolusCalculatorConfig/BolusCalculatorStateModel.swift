import SwiftUI

extension BolusCalculatorConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var overrideFactor: Decimal = 0
        @Published var useCalc: Bool = true
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var insulinReqPercentage: Decimal = 70
        @Published var displayPredictions: Bool = true
        @Published var allowBolusShortcut: Bool = false
        @Published var allowedRemoteBolusAmount: Decimal = 0
        @Published var eventualBG: Bool = false
        @Published var minumimPrediction: Bool = false
        @Published var disable15MinTrend: Bool = false
        @Published var pumpSettings: PumpSettings? = nil

        override func subscribe() async {
            let settings = await settingsManager.settings
            let pumpSettings = await settingsManager.pumpSettings
            self.pumpSettings = pumpSettings
            disable15MinTrend = settings.disable15MinTrend
            subscribeSetting(\.overrideFactor, on: $overrideFactor, initial: {
                let value = max(min($0, 2), 0.1)
                self.overrideFactor = value
            })
            subscribeSetting(\.allowBolusShortcut, on: $allowBolusShortcut) { self.allowBolusShortcut = $0 }
            subscribeSetting(\.useCalc, on: $useCalc) { self.useCalc = $0 }
            subscribeSetting(\.fattyMeals, on: $fattyMeals) { self.fattyMeals = $0 }
            subscribeSetting(\.eventualBG, on: $eventualBG) { self.eventualBG = $0 }
            subscribeSetting(\.minumimPrediction, on: $minumimPrediction) { self.minumimPrediction = $0 }
            subscribeSetting(\.displayPredictions, on: $displayPredictions) { self.displayPredictions = $0 }
            subscribeSetting(\.disable15MinTrend, on: $disable15MinTrend) { self.disable15MinTrend = $0 }

            // TODO: the values are not clamped when saving?
            subscribeSetting(\.fattyMealFactor, on: $fattyMealFactor) {
                let value = max(min($0, 1.5), 0.1)
                self.fattyMealFactor = value
            }
            subscribeSetting(\.insulinReqPercentage, on: $insulinReqPercentage) {
                let value = max(min($0, 200), 10)
                self.insulinReqPercentage = value
            }
            subscribeSetting(\.allowedRemoteBolusAmount, on: $allowedRemoteBolusAmount) {
                let value = max(min($0, settings.allowBolusShortcut ? pumpSettings.maxBolus : 0), 0)
                self.allowedRemoteBolusAmount = value
            }
        }
    }
}
