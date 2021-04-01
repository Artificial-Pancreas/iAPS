import SwiftUI

extension Settings {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section(header: Text("FreeAPS X v\(viewModel.buildNumber)")) {
                    Toggle("Closed loop", isOn: $viewModel.closedLoop)
                }

                Section(header: Text("Devices")) {
                    Text("Pump").chevronCell().navigationLink(to: .pumpConfig, from: self)
                }

                Section(header: Text("Services")) {
                    Text("Nightscout").chevronCell().navigationLink(to: .nighscoutConfig, from: self)
                }

                Section(header: Text("Configuration")) {
                    Text("Preferences").chevronCell().navigationLink(to: .preferencesEditor, from: self)
                    Text("Pump Settings").chevronCell().navigationLink(to: .pumpSettingsEditor, from: self)
                    Text("Basal Profile").chevronCell().navigationLink(to: .basalProfileEditor, from: self)
                    Text("Insulin Sensitivities").chevronCell().navigationLink(to: .isfEditor, from: self)
                    Text("Carb Ratios").chevronCell().navigationLink(to: .crEditor, from: self)
                    Text("Target Ranges").chevronCell().navigationLink(to: .targetsEditor, from: self)
                    Text("Autotune").chevronCell().navigationLink(to: .autotuneConfig, from: self)
                }

                if viewModel.debugOptions {
                    Section(header: Text("Config files")) {
                        Group {
                            Text("Preferences").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.preferences), from: self)
                            Text("Pump Settings").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.settings), from: self)
                            Text("Autosense").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autosense), from: self)
                            Text("Pump History").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
                            Text("Basal profile").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.basalProfile), from: self)
                            Text("Targets ranges").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
                            Text("Carb ratios").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.carbRatios), from: self)
                            Text("Insulin sensitivities").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.insulinSensitivities), from: self)
                            Text("Temp targets").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.tempTargets), from: self)
                            Text("Meal").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.meal), from: self)
                        }

                        Group {
                            Text("IOB").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.iob), from: self)
                            Text("Pump profile").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.pumpProfile), from: self)
                            Text("Profile").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
                            Text("Glucose").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.glucose), from: self)
                            Text("Carbs").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
                            Text("Suggested").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Enact.suggested), from: self)
                            Text("Enacted").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Enact.enacted), from: self)
                            Text("Announcements").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcements), from: self)
                            Text("Enacted announcements").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcementsEnacted), from: self)
                            Text("Autotune").chevronCell()
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autotune), from: self)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
