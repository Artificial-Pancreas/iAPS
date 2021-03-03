import SwiftUI

extension Settings {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section(header: Text("Devices")) {
                    Text("Pump").chevronCell().modal(for: .pumpConfig, from: self)
                }

                Section(header: Text("Services")) {
                    Text("Nightscout").chevronCell().modal(for: .nighscoutConfig, from: self)
                }

                Section(header: Text("Configuration")) {
                    Text("Pump settings").chevronCell().modal(for: .pumpSettingsEditor, from: self)
                    Text("Basal settings").chevronCell().modal(for: .basalProfileEditor, from: self)
                }

                Section(header: Text("Config files")) {
                    Group {
                        Text("Preferences").chevronCell()
                            .modal(for: .configEditor(file: OpenAPS.Settings.preferences), from: self)
                        Text("Pump Settings").chevronCell().modal(for: .configEditor(file: OpenAPS.Settings.settings), from: self)
                        Text("Autosense").chevronCell().modal(for: .configEditor(file: OpenAPS.Settings.autosense), from: self)
                        Text("Pump History").chevronCell()
                            .modal(for: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
                        Text("Basal profile").chevronCell()
                            .modal(for: .configEditor(file: OpenAPS.Settings.basalProfile), from: self)
                        Text("BG targets").chevronCell().modal(for: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
                        Text("Carb ratios").chevronCell().modal(for: .configEditor(file: OpenAPS.Settings.carbRatios), from: self)
                        Text("Insulin sensitivities").chevronCell()
                            .modal(for: .configEditor(file: OpenAPS.Settings.carbRatios), from: self)
                        Text("Temp targets").chevronCell()
                            .modal(for: .configEditor(file: OpenAPS.Settings.tempTargets), from: self)
                    }

                    Group {
                        Text("Glucose").chevronCell().modal(for: .configEditor(file: OpenAPS.Monitor.glucose), from: self)
                        Text("Suggested").chevronCell()
                            .modal(for: .configEditor(file: OpenAPS.Enact.suggested), from: self)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
