import SwiftUI
import Swinject

extension MainChartConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        @Environment(\.colorScheme) var colorScheme

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
            let highlightColor: Color = colorScheme == .dark
                ? Color.green
                : Color.green

            let baseColor: Color = colorScheme == .dark
                ? Color.gray
                : Color.loopGray

            let iconHeight: CGFloat = 36

            Form {
                Section {
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)
                            Image("chartVerticalLines")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }
                        Toggle("Vertical grid lines", isOn: $state.xGridLines)
                    }
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)

                            Image("chartHorizontalLines")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }
                        Toggle("Horizontal grid lines", isOn: $state.yGridLines)
                    }
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)

                            Image("chartYAxisLabels")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }
                        Toggle("Y-axis labels", isOn: $state.yGridLabels)
                    }
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)

                            Image("chartThresholdLines")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }
                        Toggle("Threshold lines (Low / High)", isOn: $state.rulerMarks)
                    }
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)

                            Image("chartInRangeHighlight")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }
                        Toggle(
                            "In-range area highlight",
                            isOn: $state.inRangeAreaFill
                        )
                    }
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)

                            Image("chartGlucosePeaks")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }

                        Toggle("Glucose peaks", isOn: $state.chartGlucosePeaks)
                    }

                    HStack {
                        HStack {
                            ZStack {
                                Image("chartBase")
                                    .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                    .foregroundStyle(baseColor)
                                    .frame(height: iconHeight)

                                Image("chartVisibleHours")
                                    .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                    .foregroundStyle(highlightColor)
                                    .frame(height: iconHeight)
                            }

                            Text("Horizontal Scroll View Visible hours")
                            DecimalTextField("6", value: $state.hours, formatter: carbsFormatter)
                        }
                    }
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)

                            Image("chartInsulinBars")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }

                        Toggle("Use insulin bars", isOn: $state.useInsulinBars)
                    }
                    HStack {
                        ZStack {
                            Image("chartBase")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(baseColor)
                                .frame(height: iconHeight)

                            Image("chartCarbBars")
                                .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                .foregroundStyle(highlightColor)
                                .frame(height: iconHeight)
                        }

                        Toggle("Use carb bars", isOn: $state.useCarbBars)
                    }
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
            .navigationBarTitle("Main Chart settings")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }
    }
}

/*
 #Preview("MainChartConfig.RootView (Icons sandbox)") {
     PreviewHost()
 }

 private struct PreviewHost: View {
     @StateObject var state = StateModelPreview()

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

     @Environment(\.colorScheme) var colorScheme

     var body: some View {
         let highlightColor: Color = colorScheme == .dark
             ? Color.cyan
             : Color.blue

         let baseColor: Color = colorScheme == .dark
             ? Color.gray
             : Color.darkerGray

         let iconHeight: CGFloat = 40

         Form {
             Section {
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)
                         Image("chartVerticalLines")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(highlightColor)
                             .frame(height: iconHeight)
                     }
                     Toggle("Vertical grid lines", isOn: $state.xGridLines)
                 }
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)

                         Image("chartHorizontalLines")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(highlightColor)
                             .frame(height: iconHeight)
                     }
                     Toggle("Horizontal grid lines", isOn: $state.yGridLines)
                 }
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)

                         Image("chartYAxisLabels")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(highlightColor)
                             .frame(height: iconHeight)
                     }
                     Toggle("Y-axis labels", isOn: $state.yGridLabels)
                 }
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)

                         Image("chartThresholdLines")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(highlightColor)
                             .frame(height: iconHeight)
                     }
                     Toggle("Threshold lines (Low / High)", isOn: $state.rulerMarks)
                 }
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)

                         Image("chartInRangeHighlight")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(.green)
                             .frame(height: iconHeight)
                     }
                     Toggle(
                         "In-range area highlight",
                         isOn: $state.inRangeAreaFill
                     )
                 }
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)

                         Image("chartGlucosePeaks")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(highlightColor)
                             .frame(height: iconHeight)
                     }

                     Toggle("Glucose peaks", isOn: $state.chartGlucosePeaks)
                 }

                 HStack {
                     HStack {
                         ZStack {
                             Image("chartBase")
                                 .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                 .foregroundStyle(baseColor)
                                 .frame(height: iconHeight)

                             Image("chartVisibleHours")
                                 .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                                 .foregroundStyle(highlightColor)
                                 .frame(height: iconHeight)
                         }

                         Text("Horizontal Scroll View Visible hours")
                         DecimalTextField("6", value: $state.hours, formatter: carbsFormatter)
                     }
                 }
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)

                         Image("chartInsulinBars")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(highlightColor)
                             .frame(height: iconHeight)
                     }

                     Toggle("Use insulin bars", isOn: $state.useInsulinBars)
                 }
                 HStack {
                     ZStack {
                         Image("chartBase")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(baseColor)
                             .frame(height: iconHeight)

                         Image("chartCarbBars")
                             .renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                             .foregroundStyle(highlightColor)
                             .frame(height: iconHeight)
                     }

                     Toggle("Use carb bars", isOn: $state.useCarbBars)
                 }
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
         .navigationBarTitle("Main Chart settings")
         .navigationBarTitleDisplayMode(.automatic)
     }

     final class StateModelPreview: ObservableObject {
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
     }
 }
 */
