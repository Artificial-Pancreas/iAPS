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
                        Text("Override with a factor of ")
                        Spacer()
                        DecimalTextField("0.8", value: $state.individualAdjustmentFactor, formatter: conversionFormatter)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Fat and Protein")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
