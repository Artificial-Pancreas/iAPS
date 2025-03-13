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
                Section(
                    header: Text("Delivery limits"),
                    footer: Text(
                        state
                            .isDanaPump ?
                            NSLocalizedString(
                                "Dana pump does not allow editing of max basal and max bolus. Configure these in the doctor's settings of the pump. Saving the settings will fetch the lastest values from the pump",
                                comment: "Dana footer"
                            ) :
                            ""
                    )
                ) {
                    HStack {
                        Text("Max Basal")
                        DecimalTextField("U/hr", value: $state.maxBasal, formatter: formatter, liveEditing: true)
                            .disabled(state.isDanaPump)
                    }
                    HStack {
                        Text("Max Bolus")
                        DecimalTextField("U", value: $state.maxBolus, formatter: formatter, liveEditing: true)
                            .disabled(state.isDanaPump)
                    }
                }

                Section(header: Text("Duration of Insulin Action")) {
                    HStack {
                        Text("DIA")
                        DecimalTextField("hours", value: $state.dia, formatter: formatter, liveEditing: true)
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
                            Text(state.syncInProgress ? "Saving..." : !state.isDanaPump ? "Save on Pump" : "Save")
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
