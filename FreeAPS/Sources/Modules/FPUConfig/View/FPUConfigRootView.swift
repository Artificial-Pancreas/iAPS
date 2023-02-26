import SwiftUI
import Swinject

extension FPUConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var intFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Convert Fat and Protein")) {
                    Toggle("Enable", isOn: $state.useFPUconversion)
                }

                Section(header: Text("Optional conversion settings")) {
                    HStack {
                        Text("Delay In Minutes")
                        Spacer()
                        DecimalTextField("8", value: $state.delay, formatter: intFormater)
                    }
                    HStack {
                        Text("Maximum Time Cap In Hours")
                        Spacer()
                        DecimalTextField("8", value: $state.timeCap, formatter: intFormater)
                    }
                    HStack {
                        Text("Interval In Minutes")
                        Spacer()
                        DecimalTextField("60", value: $state.minuteInterval, formatter: intFormater)
                    }
                    HStack {
                        Text("Override With A Factor Of ")
                        Spacer()
                        DecimalTextField("0.8", value: $state.individualAdjustmentFactor, formatter: conversionFormatter)
                    }
                }

                Section(
                    footer: Text(
                        "Allows fat and protein to be converted to future carb equivalents. Delay is when the first future carb equivalent is created. Maximum time is the maximum number of hours in total all of the carb equivalents will allocate. Interval means number of minutes betewwen the created future carb entries. Override setting is for safety and for tuning of the conversion to carbs, recommended 0.5-0.8. The higher, the larger the total amount of future carbs.\n\nDefault settings: Delay: 60 min, Time Cap: 8 h, Interval: 60 min, Factor: 0.5."
                    )
                )
                    {}
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Fat and Protein")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
