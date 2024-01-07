import SwiftUI
import Swinject

extension BolusCalculatorConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var conversionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1

            return formatter
        }

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Toggle("Use alternate Bolus Calculator", isOn: $state.useCalc)
                    }

                    if state.useCalc {
                        HStack {
                            Text("Override With A Factor Of ")
                            Spacer()
                            DecimalTextField("0.8", value: $state.overrideFactor, formatter: conversionFormatter)
                        }
                    }

                    if !state.useCalc {
                        HStack {
                            Text("Recommended Bolus Percentage")
                            DecimalTextField("", value: $state.insulinReqPercentage, formatter: formatter)
                        }
                    }
                } header: { Text("Calculator settings") }

                Section {
                    Toggle("Display Predictions", isOn: $state.displayPredictions)

                } header: { Text("Smaller iPhone Screens") }

                if state.useCalc {
                    Section {
                        HStack {
                            Toggle("Apply factor for fatty meals", isOn: $state.fattyMeals)
                        }
                        HStack {
                            Text("Override With A Factor Of ")
                            Spacer()
                            DecimalTextField("0.7", value: $state.fattyMealFactor, formatter: conversionFormatter)
                        }
                    } header: { Text("Fatty Meals") }

                    Section {}
                    footer: { Text(
                        "The new alternate bolus calculator is another approach to the default bolus calculator in iAPS. If the toggle is on you use this bolus calculator and not the original iAPS calculator. At the end of the calculation a custom factor is applied as it is supposed to be when using smbs (default 0.8).\n\nYou can also add the option in your bolus calculator to apply another (!) customizable factor at the end of the calculation which could be useful for fatty meals, e.g Pizza (default 0.7)."
                    )
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationBarTitle("Bolus Calculator")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
