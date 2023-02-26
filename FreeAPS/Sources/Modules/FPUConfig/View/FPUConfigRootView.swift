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

                Section(header: Text("Conversion settings")) {
                    HStack {
                        Text("Delay In Minutes")
                        Spacer()
                        DecimalTextField("8", value: $state.delay, formatter: intFormater)
                    }
                    HStack {
                        Text("Maximum Duration In Hours")
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
                        "Allows fat and protein to be converted into future carb equivalents, using the Warsaw method (total kcal/10).\n\nDelay is time from now until first future carb entry. Maximum duration is the maximum time in hours, in total, which the carb equivalents will allocate. Interval means the number of minutes betewen these entries. Override setting is for safety and tuning. The higher, the larger the total amount of carb equivalents. Compensating for an increased total carb amount with an increased IC ratio is recommended.\n\nDefault settings: Delay: 60 min, Time Cap: 8 h, Interval: 60 min, Factor: 0.5."
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
