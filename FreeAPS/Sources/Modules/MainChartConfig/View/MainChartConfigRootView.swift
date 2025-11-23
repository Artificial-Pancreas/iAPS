import SwiftUI
import Swinject

extension MainChartConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var insulinFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    Toggle("Vertical grid lines", isOn: $state.xGridLines)
                    Toggle("Horizontal grid lines", isOn: $state.yGridLines)
                    Toggle("Y-axis labels", isOn: $state.yGridLabels)
                    Toggle("Threshold lines (Low / High)", isOn: $state.rulerMarks)
                    Toggle("In-range area highlight", isOn: $state.inRangeAreaFill)
                    Toggle("Glucose peaks", isOn: $state.chartGlucosePeaks)

                    HStack {
                        Text("Horizontal Scroll View Visible hours")
                        Spacer()
                        DecimalTextField("6", value: $state.hours, formatter: carbsFormatter)
                        Text("hours").foregroundColor(.secondary)
                    }
                    Toggle("Use insulin bars", isOn: $state.useInsulinBars)
                    Toggle("Use carb bars", isOn: $state.useCarbBars)
                    HStack {
                        Text("Hide the bolus amount strings when amount is under")
                        Spacer()
                        DecimalTextField("0.2", value: $state.minimumSMB, formatter: insulinFormatter)
                        Text("U").foregroundColor(.secondary)
                    }
                    Toggle("Display carb equivalents", isOn: $state.fpus)
                    if state.fpus {
                        Toggle("Display carb equivalent amount", isOn: $state.fpuAmounts)
                    }
                    Toggle("Hide Predictions", isOn: $state.hidePredictions)
                    if !state.hidePredictions {
                        Toggle("Predictions legend", isOn: $state.showPredictionsLegend)
                    }
                }

                Section {
                    Toggle("Display Insulin Activity Chart", isOn: $state.showInsulinActivity)
                    Toggle("Display COB Chart", isOn: $state.showCobChart)
                    if state.showInsulinActivity || state.showCobChart {
                        Toggle("Secondary chart backdrop", isOn: $state.secondaryChartBackdrop)
                    }

                    if state.showInsulinActivity {
                        Toggle("Insulin activity grid lines", isOn: $state.insulinActivityGridLines)
                        Toggle("Insulin activity labels", isOn: $state.insulinActivityLabels)
                    }
                } header: {
                    Text("Secondary chart")
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationBarTitle("Home Chart settings")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }
    }
}
