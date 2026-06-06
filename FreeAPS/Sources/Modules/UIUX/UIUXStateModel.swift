import SwiftUI

extension UIUX {
    final class StateModel: BaseStateModel<Provider> {
        @Published var overrideHbA1cUnit = false
        @Published var low: Decimal = 4 / 0.0555
        @Published var high: Decimal = 10 / 0.0555
        @Published var oneDimensionalGraph = false
        @Published var skipBolusScreenAfterCarbs: Bool = false
        @Published var useFPUconversion: Bool = true
        @Published var useTargetButton: Bool = false
        @Published var alwaysUseColors: Bool = false
        @Published var skipGlucoseChart: Bool = false
        @Published var displayDelta: Bool = false
        @Published var hideInsulinBadge: Bool = false
        @Published var displayExpiration: Bool = false
        @Published var displaySAGE: Bool = true
        @Published var carbButton: Bool = true
        @Published var profileButton: Bool = true
        @Published var lightMode: LightMode = .auto
        @Published var ai: Bool = true
        @Published var mealViewMicronutrients: Bool = true

        var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            let settings = await settingsManager.settings
            units = settings.units

            subscribeSetting(\.overrideHbA1cUnit, on: $overrideHbA1cUnit) { self.overrideHbA1cUnit = $0 }
            subscribeSetting(\.skipGlucoseChart, on: $skipGlucoseChart) { self.skipGlucoseChart = $0 }
            subscribeSetting(\.alwaysUseColors, on: $alwaysUseColors) { self.alwaysUseColors = $0 }
            subscribeSetting(\.useFPUconversion, on: $useFPUconversion) { self.useFPUconversion = $0 }
            subscribeSetting(\.useTargetButton, on: $useTargetButton) { self.useTargetButton = $0 }
            subscribeSetting(\.skipBolusScreenAfterCarbs, on: $skipBolusScreenAfterCarbs) { self.skipBolusScreenAfterCarbs = $0 }
            subscribeSetting(\.oneDimensionalGraph, on: $oneDimensionalGraph) { self.oneDimensionalGraph = $0 }
            subscribeSetting(\.displayDelta, on: $displayDelta) { self.displayDelta = $0 }
            subscribeSetting(\.hideInsulinBadge, on: $hideInsulinBadge) { self.hideInsulinBadge = $0 }
            subscribeSetting(\.displayExpiration, on: $displayExpiration) { self.displayExpiration = $0 }
            subscribeSetting(\.displaySAGE, on: $displaySAGE) { self.displaySAGE = $0 }
            subscribeSetting(\.carbButton, on: $carbButton) { self.carbButton = $0 }
            subscribeSetting(\.profileButton, on: $profileButton) { self.profileButton = $0 }
            subscribeSetting(\.lightMode, on: $lightMode) { self.lightMode = $0 }
            subscribeSetting(\.ai, on: $ai) { self.ai = $0 }
            subscribeSetting(\.mealViewMicronutrients, on: $mealViewMicronutrients) { self.mealViewMicronutrients = $0 }

            subscribeSetting(\.low, on: $low, initial: {
                let value = max(min($0, 90), 40)
                self.low = self.units == .mmolL ? value.asMmolL : value
            }, map: {
                guard self.units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.high, on: $high, initial: {
                let value = max(min($0, 270), 110)
                self.high = self.units == .mmolL ? value.asMmolL : value
            }, map: {
                guard self.units == .mmolL else { return $0 }
                return $0.asMgdL
            })
        }
    }
}
