import SwiftUI
import Swinject

extension PumpSettingsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        @FetchRequest(
            entity: InsulinConcentration.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]
        ) var concentration: FetchedResults<InsulinConcentration>

        var body: some View {
            Form {
                Section(header: Text("Delivery limits")) {
                    HStack {
                        Text("Max Basal")
                        DecimalTextField("U/hr", value: $state.maxBasal, formatter: formatter)
                    }
                    HStack {
                        Text("Max Bolus")
                        DecimalTextField("U", value: $state.maxBolus, formatter: formatter)
                    }
                }

                Section(header: Text("Duration of Insulin Action")) {
                    HStack {
                        Text("DIA")
                        DecimalTextField("hours", value: $state.dia, formatter: formatter)
                    }
                }

                Section {
                    Text("U " + (formatter.string(from: (concentration.last?.concentration ?? 1) * 100 as NSNumber) ?? ""))
                        .navigationLink(to: .basalProfileEditor(saveNewConcentration: true), from: self)
                } header: { Text("Concentration") }

                Section {
                    HStack {
                        if state.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button { state.save() }
                        label: {
                            Text(state.syncInProgress ? "Saving..." : "Save on Pump")
                        }
                        .disabled(state.syncInProgress)
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Pump Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
