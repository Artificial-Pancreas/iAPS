import SwiftUI

extension MainChartConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var xGridLines = false
        @Published var yGridLines: Bool = false
        @Published var yGridLabels: Bool = false
        @Published var rulerMarks: Bool = false
        @Published var inRangeAreaFill: Bool = false
        @Published var secondaryChartBackdrop: Bool = false
        @Published var insulinActivityGridLines: Bool = true
        @Published var insulinActivityLabels: Bool = true
        @Published var chartGlucosePeaks: Bool = false
        @Published var showPredictionsLegend: Bool = true
        @Published var useFPUconversion: Bool = true
        @Published var hours: Decimal = 6
        @Published var alwaysUseColors: Bool = false
        @Published var minimumSMB: Decimal = 0.3
        @Published var useInsulinBars: Bool = false
        @Published var skipGlucoseChart: Bool = false
        @Published var hideInsulinBadge: Bool = false
        @Published var fpus: Bool = true
        @Published var fpuAmounts: Bool = false
        @Published var showInsulinActivity: Bool = false
        @Published var showCobChart: Bool = false
        @Published var hidePredictions: Bool = false
        @Published var useCarbBars: Bool = false

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.xGridLines, on: $xGridLines) { xGridLines = $0 }
            subscribeSetting(\.yGridLines, on: $yGridLines) { yGridLines = $0 }
            subscribeSetting(\.yGridLabels, on: $yGridLabels) { yGridLabels = $0 }
            subscribeSetting(\.rulerMarks, on: $rulerMarks) { rulerMarks = $0 }
            subscribeSetting(\.inRangeAreaFill, on: $inRangeAreaFill) { inRangeAreaFill = $0 }
            subscribeSetting(\.secondaryChartBackdrop, on: $secondaryChartBackdrop) { secondaryChartBackdrop = $0 }
            subscribeSetting(\.insulinActivityGridLines, on: $insulinActivityGridLines) { insulinActivityGridLines = $0 }
            subscribeSetting(\.insulinActivityLabels, on: $insulinActivityLabels) { insulinActivityLabels = $0 }
            subscribeSetting(\.chartGlucosePeaks, on: $chartGlucosePeaks) { chartGlucosePeaks = $0 }
            subscribeSetting(\.showPredictionsLegend, on: $showPredictionsLegend) { showPredictionsLegend = $0 }
            subscribeSetting(\.skipGlucoseChart, on: $skipGlucoseChart) { skipGlucoseChart = $0 }
            subscribeSetting(\.alwaysUseColors, on: $alwaysUseColors) { alwaysUseColors = $0 }
            subscribeSetting(\.useFPUconversion, on: $useFPUconversion) { useFPUconversion = $0 }
            subscribeSetting(\.useInsulinBars, on: $useInsulinBars) { useInsulinBars = $0 }
            subscribeSetting(\.hideInsulinBadge, on: $hideInsulinBadge) { hideInsulinBadge = $0 }
            subscribeSetting(\.fpus, on: $fpus) { fpus = $0 }
            subscribeSetting(\.fpuAmounts, on: $fpuAmounts) { fpuAmounts = $0 }
            subscribeSetting(\.showInsulinActivity, on: $showInsulinActivity) { showInsulinActivity = $0 }
            subscribeSetting(\.showCobChart, on: $showCobChart) { showCobChart = $0 }
            subscribeSetting(\.hidePredictions, on: $hidePredictions) { hidePredictions = $0 }
            subscribeSetting(\.useCarbBars, on: $useCarbBars) { useCarbBars = $0 }

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
