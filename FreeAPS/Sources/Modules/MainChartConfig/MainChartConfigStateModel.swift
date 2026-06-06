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

        @Published var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            let settings = await settingsManager.settings
            let units = settings.units
            self.units = units

            subscribeSetting(\.xGridLines, on: $xGridLines) { self.xGridLines = $0 }
            subscribeSetting(\.yGridLines, on: $yGridLines) { self.yGridLines = $0 }
            subscribeSetting(\.yGridLabels, on: $yGridLabels) { self.yGridLabels = $0 }
            subscribeSetting(\.rulerMarks, on: $rulerMarks) { self.rulerMarks = $0 }
            subscribeSetting(\.inRangeAreaFill, on: $inRangeAreaFill) { self.inRangeAreaFill = $0 }
            subscribeSetting(\.secondaryChartBackdrop, on: $secondaryChartBackdrop) { self.secondaryChartBackdrop = $0 }
            subscribeSetting(\.insulinActivityGridLines, on: $insulinActivityGridLines) { self.insulinActivityGridLines = $0 }
            subscribeSetting(\.insulinActivityLabels, on: $insulinActivityLabels) { self.insulinActivityLabels = $0 }
            subscribeSetting(\.chartGlucosePeaks, on: $chartGlucosePeaks) { self.chartGlucosePeaks = $0 }
            subscribeSetting(\.showPredictionsLegend, on: $showPredictionsLegend) { self.showPredictionsLegend = $0 }
            subscribeSetting(\.skipGlucoseChart, on: $skipGlucoseChart) { self.skipGlucoseChart = $0 }
            subscribeSetting(\.alwaysUseColors, on: $alwaysUseColors) { self.alwaysUseColors = $0 }
            subscribeSetting(\.useFPUconversion, on: $useFPUconversion) { self.useFPUconversion = $0 }
            subscribeSetting(\.useInsulinBars, on: $useInsulinBars) { self.useInsulinBars = $0 }
            subscribeSetting(\.hideInsulinBadge, on: $hideInsulinBadge) { self.hideInsulinBadge = $0 }
            subscribeSetting(\.fpus, on: $fpus) { self.fpus = $0 }
            subscribeSetting(\.fpuAmounts, on: $fpuAmounts) { self.fpuAmounts = $0 }
            subscribeSetting(\.showInsulinActivity, on: $showInsulinActivity) { self.showInsulinActivity = $0 }
            subscribeSetting(\.showCobChart, on: $showCobChart) { self.showCobChart = $0 }
            subscribeSetting(\.hidePredictions, on: $hidePredictions) { self.hidePredictions = $0 }
            subscribeSetting(\.useCarbBars, on: $useCarbBars) { self.useCarbBars = $0 }

            subscribeSetting(\.hours, on: $hours.map(Int.init)) {
                let value = max(min($0, 24), 2)
                self.hours = Decimal(value)
            }

            subscribeSetting(\.minimumSMB, on: $minimumSMB) {
                self.minimumSMB = max(min($0, 10), 0)
            }
        }
    }
}
