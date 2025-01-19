import SwiftUI
import Swinject

extension StatConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

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
                    Toggle("Display Chart X - Grid lines", isOn: $state.xGridLines)
                    Toggle("Display Chart Y - Grid lines", isOn: $state.yGridLines)
                    Toggle("Display Chart Threshold lines for Low and High", isOn: $state.rulerMarks)
                    Toggle("Standing / Laying TIR Chart", isOn: $state.oneDimensionalGraph)
                    HStack {
                        Text("Horizontal Scroll View Visible hours")
                        Spacer()
                        DecimalTextField("6", value: $state.hours, formatter: carbsFormatter)
                        Text("hours").foregroundColor(.secondary)
                    }
                    Toggle("Use insulin bars", isOn: $state.useInsulinBars)
                    HStack {
                        Text("Hide the bolus amount strings when amount is under")
                        Spacer()
                        DecimalTextField("0.2", value: $state.minimumSMB, formatter: insulinFormatter)
                        Text("U").foregroundColor(.secondary)
                    }

                } header: { Text("Home Chart settings ") }

                Section {
                    Toggle("Display Temp Targets Button", isOn: $state.useTargetButton)
                } header: { Text("Home View Button Panel ") }
                footer: { Text("In case you're using both profiles and temp targets") }

                Section {
                    Toggle("Never display the small glucose chart when scrolling", isOn: $state.skipGlucoseChart)
                    Toggle("Always Color Glucose Value (green, yellow etc)", isOn: $state.alwaysUseColors)
                    Toggle("Display Glucose Delta", isOn: $state.displayDelta)
                    Toggle("Hide Concentration Badge", isOn: $state.hideInsulinBadge)
                } header: { Text("Header settings") }

                Section {
                    HStack {
                        Text("Low")
                        Spacer()
                        DecimalTextField("0", value: $state.low, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("High")
                        Spacer()
                        DecimalTextField("0", value: $state.high, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    Toggle("Override HbA1c Unit", isOn: $state.overrideHbA1cUnit)

                } header: { Text("Statistics settings ") }

                Section {
                    Toggle("Skip Bolus screen after carbs", isOn: $state.skipBolusScreenAfterCarbs)
                    Toggle("Display and allow Fat and Protein entries", isOn: $state.useFPUconversion)
                } header: { Text("Add Meal View settings ") }

                Section {
                    Toggle(isOn: $state.extendHomeView) {
                        Text("Display Ratio and a History View button")
                    }
                } header: { Text("Auto ISF Home View") }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationBarTitle("UI/UX")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }
    }
}
