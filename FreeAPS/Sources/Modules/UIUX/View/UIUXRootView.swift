import SwiftUI
import Swinject

extension UIUX {
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
                    Text("Main Chart settings").navigationLink(to: .mainChartConfig, from: self)
                } header: { Text("Main Chart") }

                Section {
                    Toggle("Display Temp Targets Button", isOn: $state.useTargetButton)
                    Toggle("Display Profile Override Button", isOn: $state.profileButton)
                    Toggle("Display Meal Button", isOn: $state.carbButton)
                } header: { Text("Home View Button Panel ") }

                Section {
                    Toggle("Never display the small glucose chart when scrolling", isOn: $state.skipGlucoseChart)
                    Toggle("Always Color Glucose Value (green, yellow etc)", isOn: $state.alwaysUseColors)
                    Toggle("Display Glucose Delta", isOn: $state.displayDelta)
                    Toggle("Hide Concentration Badge", isOn: $state.hideInsulinBadge)
                    Toggle("Display Sensor Age", isOn: $state.displaySAGE)
                    Toggle("Display Sensor Time Remaining", isOn: $state.displayExpiration)
                } header: { Text("Header settings") }
                    ._onBindingChange($state.displaySAGE) { enabled in
                        if enabled { state.displayExpiration = false }
                    }
                    ._onBindingChange($state.displayExpiration) { enabled in
                        if enabled { state.displaySAGE = false }
                    }

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
                    Toggle("Standing / Laying TIR Chart", isOn: $state.oneDimensionalGraph)

                } header: { Text("Statistics settings ") }

                Section {
                    Toggle("Skip Bolus screen after carbs", isOn: $state.skipBolusScreenAfterCarbs)
                    Toggle("Display and allow Fat and Protein entries", isOn: $state.useFPUconversion)
                    Toggle("AI Food Search", isOn: $state.ai)

                    if state.ai {
                        Toggle("Don't ask for saving search result as meal preset", isOn: $state.skipSave)
                    }
                } header: { Text("Add Meal View settings ") }

                Section {
                    Picker(selection: $state.lightMode, label: Text("Color Scheme")) {
                        ForEach(LightMode.allCases) { item in
                            Text(NSLocalizedString(item.rawValue, comment: "ColorScheme Selection"))
                        }
                    }
                } header: { Text("Light / Dark Mode") }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationBarTitle("UI/UX")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }
    }
}
