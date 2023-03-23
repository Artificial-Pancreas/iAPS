import CoreData
import SwiftUI
import Swinject

extension OverrideProfilesConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State private var isEditing = false
        @State private var showAlert = false

        @FetchRequest(
            entity: Override.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var fetchedPercent: FetchedResults<Override>

        @Environment(\.managedObjectContext) var moc

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Override your Basal, ISF and CR profiles")) {
                    Toggle(isOn: $state.isEnabled) {
                        Text("Override Profiles")
                    }._onBindingChange($state.isEnabled, perform: { _ in
                        if !state.isEnabled {
                            let isEnabledMoc = Override(context: moc)
                            isEnabledMoc.enabled = false
                            isEnabledMoc.percentage = 100
                            isEnabledMoc.date = Date()
                            try? moc.save()
                        }
                    })
                }
                if state.isEnabled {
                    Section(
                        header: Text("Total Insulin Adjustment"),
                        footer: Text(
                            "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage.\n\nWhen you toggle of the override or return the slider to 100% every profile setting will return to normal."
                        )
                    ) {
                        VStack {
                            Slider(
                                value: $state.percentage,
                                in: 10 ... 200,
                                step: 1,
                                onEditingChanged: { editing in
                                    isEditing = editing
                                }
                            )
                            Text("\(state.percentage.formatted(.number)) %")
                                .foregroundColor(isEditing ? .orange : .blue)
                                .font(.largeTitle)
                            Spacer()
                            Toggle(isOn: $state._indefinite) {
                                Text("Enable indefinitely")
                            }
                        }
                        if !state._indefinite {
                            HStack {
                                Text("Duration")
                                DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                                Text("hours").foregroundColor(.secondary)
                            }
                        }
                        Button("Save") {
                            showAlert.toggle()
                        }
                        .disabled(
                            state.isEnabled == false || state
                                .percentage == 100 || (!state._indefinite && state.duration == 0)
                        )
                        .accentColor(.orange)
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .controlSize(.mini)
                        .alert(
                            "Saving this override will change your basal insulin, ISF and CR during the entire selected duration. Tapping save will start your new overide or edit your current active override.",
                            isPresented: $showAlert,
                            actions: {
                                Button("Cancel", role: .cancel) {}
                                Button("Start Override", role: .destructive) {
                                    let isEnabledMoc = Override(context: moc)
                                    isEnabledMoc.indefinite = state._indefinite
                                    isEnabledMoc.percentage = state.percentage
                                    if state.percentage == 100 {
                                        isEnabledMoc.enabled = false
                                    } else { isEnabledMoc.enabled = true }
                                    isEnabledMoc.date = Date()
                                    isEnabledMoc.duration = state.duration as NSDecimalNumber
                                    if state._indefinite {
                                        isEnabledMoc.duration = 0
                                    } else if state.duration == 0 {
                                        isEnabledMoc.enabled = false
                                    } else { isEnabledMoc.timeLeft = Double(state.duration) }
                                    try? moc.save()
                                }
                            }
                        )
                    }
                }
            }.onAppear { state.savedSettings() }
        }
    }
}
