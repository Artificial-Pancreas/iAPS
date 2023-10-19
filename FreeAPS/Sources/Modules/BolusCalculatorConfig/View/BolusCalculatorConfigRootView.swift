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

        var body: some View {
            Form {
                Section(header: Text("Calculator settings")) {
                    HStack {
                        Text("Override With A Factor Of ")
                        Spacer()
                        DecimalTextField("0.8", value: $state.overrideFactor, formatter: conversionFormatter)
                    }
                    HStack {
                        Toggle("Use alternative Bolus Calculator", isOn: $state.useCalc)
                    }
                }

                Section(
                    footer: Text(
                        "This is another approach to the bolus calculator integrated in iAPS. If the toggle is on you use this bolus calculator and not the original iAPS calculator. You can exclude parts of the calculation as you like. At the end of the calculation a (default) factor of 0.8 is applied as it is supposed to be when using smbs. Of course this value is adjustable. Feel free to test!"
                    )
                )
                    {}
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Bolus Calculator")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
