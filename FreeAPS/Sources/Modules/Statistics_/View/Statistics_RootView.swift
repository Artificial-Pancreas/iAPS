import SwiftUI
import Swinject

extension Statistics_ {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var oneFractionDigitFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var twoFractionDigitsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Settings")) {
                    HStack {
                        Toggle("Override HbA1c unit", isOn: $state.overrideHbA1cUnit)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
