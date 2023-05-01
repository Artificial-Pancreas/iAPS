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

        var body: some View {
            Form {
                Section(header: Text("Settings")) {
                    Toggle("Change HbA1c Unit", isOn: $state.overrideHbA1cUnit)
                    Toggle("Allow Upload of Statistics to NS", isOn: $state.uploadStats)
                    Toggle("Display X - Grid lines", isOn: $state.xGridLines)
                    Toggle("Display Y - Grid lines", isOn: $state.yGridLines)
                    Toggle("Standing / Laying TIR Chart", isOn: $state.oneDimensionalGraph)

                    HStack {
                        Text("Hours (X-Axis)")
                        Spacer()
                        DecimalTextField("6", value: $state.hours, formatter: carbsFormatter)
                        Text("hours").foregroundColor(.secondary)
                    }

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
                }
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Statistics")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
