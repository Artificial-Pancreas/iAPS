import SwiftUI

extension UIUX {
    final class StateModel: BaseStateModel<Provider> {
        @Published var overrideHbA1cUnit = false
        @Published var low: Decimal = 4 / 0.0555
        @Published var high: Decimal = 10 / 0.0555
        @Published var xGridLines = false
        @Published var yGridLines: Bool = false
        @Published var oneDimensionalGraph = false
        @Published var rulerMarks: Bool = false
        @Published var skipBolusScreenAfterCarbs: Bool = false
        @Published var useFPUconversion: Bool = true
        @Published var useTargetButton: Bool = false
        @Published var hours: Decimal = 6
        @Published var alwaysUseColors: Bool = false
        @Published var minimumSMB: Decimal = 0.3
        @Published var useInsulinBars: Bool = false
        @Published var skipGlucoseChart: Bool = false
        @Published var displayDelta: Bool = false
        @Published var hideInsulinBadge: Bool = false
        @Published var displayExpiration: Bool = false
        @Published var displaySAGE: Bool = true
        @Published var fpus: Bool = true
        @Published var fpuAmounts: Bool = false
        @Published var carbButton: Bool = true
        @Published var profileButton: Bool = true
        @Published var lightMode: LightMode = .auto
        @Published var showInsulinActivity: Bool = false
        @Published var showCobChart: Bool = false
        @Published var hidePredictions: Bool = false

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.overrideHbA1cUnit, on: $overrideHbA1cUnit) { overrideHbA1cUnit = $0 }
            subscribeSetting(\.xGridLines, on: $xGridLines) { xGridLines = $0 }
            subscribeSetting(\.yGridLines, on: $yGridLines) { yGridLines = $0 }
            subscribeSetting(\.rulerMarks, on: $rulerMarks) { rulerMarks = $0 }
            subscribeSetting(\.skipGlucoseChart, on: $skipGlucoseChart) { skipGlucoseChart = $0 }
            subscribeSetting(\.alwaysUseColors, on: $alwaysUseColors) { alwaysUseColors = $0 }
            subscribeSetting(\.useFPUconversion, on: $useFPUconversion) { useFPUconversion = $0 }
            subscribeSetting(\.useTargetButton, on: $useTargetButton) { useTargetButton = $0 }
            subscribeSetting(\.skipBolusScreenAfterCarbs, on: $skipBolusScreenAfterCarbs) { skipBolusScreenAfterCarbs = $0 }
            subscribeSetting(\.oneDimensionalGraph, on: $oneDimensionalGraph) { oneDimensionalGraph = $0 }
            subscribeSetting(\.useInsulinBars, on: $useInsulinBars) { useInsulinBars = $0 }
            subscribeSetting(\.displayDelta, on: $displayDelta) { displayDelta = $0 }
            subscribeSetting(\.hideInsulinBadge, on: $hideInsulinBadge) { hideInsulinBadge = $0 }
            subscribeSetting(\.displayExpiration, on: $displayExpiration) { displayExpiration = $0 }
            subscribeSetting(\.displaySAGE, on: $displaySAGE) { displaySAGE = $0 }
            subscribeSetting(\.fpus, on: $fpus) { fpus = $0 }
            subscribeSetting(\.fpuAmounts, on: $fpuAmounts) { fpuAmounts = $0 }
            subscribeSetting(\.carbButton, on: $carbButton) { carbButton = $0 }
            subscribeSetting(\.profileButton, on: $profileButton) { profileButton = $0 }
            subscribeSetting(\.lightMode, on: $lightMode) { lightMode = $0 }
            subscribeSetting(\.showInsulinActivity, on: $showInsulinActivity) { showInsulinActivity = $0 }
            subscribeSetting(\.showCobChart, on: $showCobChart) { showCobChart = $0 }
            subscribeSetting(\.hidePredictions, on: $hidePredictions) { hidePredictions = $0 }

            subscribeSetting(\.low, on: $low, initial: {
                let value = max(min($0, 90), 40)
                low = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.high, on: $high, initial: {
                let value = max(min($0, 270), 110)
                high = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.hours, on: $hours.map(Int.init), initial: {
                let value = max(min($0, 24), 2)
                hours = Decimal(value)
            }, map: {
                $0
            })

            subscribeSetting(\.minimumSMB, on: $minimumSMB, initial: {
                minimumSMB = max(min($0, 10), 0)
            }, map: {
                $0
            })
        }
    }
}
