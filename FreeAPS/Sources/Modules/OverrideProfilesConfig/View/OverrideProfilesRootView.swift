import CoreData
import SwiftUI
import Swinject

extension OverrideProfilesConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State private var isEditing = false
        @State private var showAlert = false
        @State private var showingDetail = false
        @State private var isPresented = true
        @Environment(\.dismiss) var dismiss

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        var body: some View {
            Form {
                Section(
                    header: Text("Override your Basal, ISF and CR profiles"),
                    footer: Text("" + (!state.isEnabled ? "Currently no Override active" : ""))
                ) {
                    Toggle(isOn: $state.isEnabled) {
                        Text("Override Profiles")
                    }._onBindingChange($state.isEnabled, perform: { _ in
                        if !state.isEnabled {
                            state.duration = 0
                            state.percentage = 100
                            state._indefinite = false
                            state.saveSettings()
                        }
                    })
                }
                if state.isEnabled {
                    Section(
                        header: Text("Total Insulin Adjustment"),
                        footer: Text(
                            "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage.\n\nIf you toggle off the override every profile setting will return to normal."
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
                            ).accentColor(state.percentage >= 130 ? .red : .blue)
                            Text("\(state.percentage.formatted(.number)) %")
                                .foregroundColor(
                                    state
                                        .percentage >= 130 ? .red :
                                        (isEditing ? .orange : .blue)
                                )
                                .font(.largeTitle)
                            Spacer()
                            Toggle(isOn: $state._indefinite) {
                                Text("Enable indefinitely")
                            }
                        }
                        if !state._indefinite {
                            HStack {
                                Text("Duration")
                                DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: false)
                                Text("minutes").foregroundColor(.secondary)
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
                            "Selected Override:\n\n\(state.percentage.formatted(.number)) %, " +
                                (state.duration > 0 ? "\(state.duration) min" : " infinite duration.") + "\n\n" +
                                "Saving this override will change your basal insulin, ISF and CR during the entire selected duration. Tapping save will start your new overide or edit your current active override.",
                            isPresented: $showAlert,
                            actions: {
                                Button("Cancel", role: .cancel) {}
                                Button("Start Override", role: .destructive) {
                                    if state.percentage == 100 {
                                        state.isEnabled = false
                                    } else { state.isEnabled = true }
                                    if state._indefinite {
                                        state.duration = 0
                                    } else if state.duration == 0 {
                                        state.isEnabled = false
                                    }
                                    state.saveSettings()
                                    dismiss()
                                }
                            }
                        )
                    }
                }
            }.onAppear { state.savedSettings() }
        }
    }
}
