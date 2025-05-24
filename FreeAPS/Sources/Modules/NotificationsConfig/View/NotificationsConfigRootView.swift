import ActivityKit
import AVFoundation
import Combine
import SwiftUI
import Swinject

extension NotificationsConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var currentSoundID: SystemSoundID = 1336
        @State private var isPlay = false
        @State private var currentName: String = ""

        let soundManager = SystemSoundsManager()
        let silent = "Silent"
        let defaultSound = "Default"

        @State private var systemLiveActivitySetting: Bool = { ActivityAuthorizationInfo().areActivitiesEnabled }()

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private func liveActivityFooterText() -> String {
            var footer =
                "Live activity displays blood glucose live on the lock screen and on the dynamic island (if available)"

            if !systemLiveActivitySetting {
                footer =
                    NSLocalizedString(
                        "Live activities are turned OFF in system settings. To enable live activities, go to Settings app -> iAPS -> Turn live Activities ON.\n\n",
                        comment: "footer"
                    ) + NSLocalizedString(footer, comment: "Footer")
            }

            return footer
        }

        private func playSound(_ s: String? = nil, _ sStop: SystemSoundID? = nil, _ onCompletion: @escaping () -> Void) {
            guard state.alarmSound != "Silent" else { return }

            if sStop != nil {
                AudioServicesDisposeSystemSoundID(sStop!)
                return
            }
            let path = "/System/Library/Audio/UISounds/" + (s ?? state.alarmSound)
            var theSoundID = SystemSoundID(1336)
            let soundURL = URL(string: path)
            AudioServicesCreateSystemSoundID(soundURL! as CFURL, &theSoundID)
            currentSoundID = theSoundID
            AudioServicesPlaySystemSoundWithCompletion(theSoundID) {
                AudioServicesDisposeSystemSoundID(theSoundID)
                onCompletion()
            }
        }

        private func cut(_ name: String) -> String {
            name
                .replacingOccurrences(of: ".caf", with: "")
                .replacingOccurrences(of: "New/", with: "")
                .replacingOccurrences(of: "Modern/", with: "")
                .replacingOccurrences(of: "nano/", with: "")
                .replacingOccurrences(of: "_", with: " ")
        }

        private func soundView(name: String) -> some View {
            Image(systemName: "playpause.fill")
                .foregroundStyle(.blue)
                .onTapGesture {
                    currentName = name
                    if isPlay {
                        playSound(name, currentSoundID) {
                            isPlay = false
                            currentName = ""
                        }
                    } else {
                        playSound(name) {
                            isPlay = false
                            currentName = ""
                        }
                    }
                    isPlay = true
                }
        }

        private func buttonView(name: String) -> some View {
            HStack(spacing: 20) {
                soundView(name: name)
                Text(cut(name))
            }
        }

        private var silentView: some View {
            Text("Silent").padding(.leading, 46)
        }

        private var defaultView: some View {
            Text("Default").padding(.leading, 46)
        }

        var body: some View {
            Form {
                Section {
                    Toggle("Show glucose on the app badge", isOn: $state.glucoseBadge)
                    Toggle("Always Notify Glucose", isOn: $state.glucoseNotificationsAlways)
                    Toggle("Also add source info", isOn: $state.addSourceInfoToGlucoseNotifications)
                    Toggle("Low", isOn: $state.lowAlert)
                    Toggle("High", isOn: $state.highAlert)
                    Toggle("Ascending", isOn: $state.ascendingAlert)
                    Toggle("Descending", isOn: $state.descendingAlert)
                    Toggle("Carbs required", isOn: $state.carbsRequiredAlert)
                    Toggle("Also play alert sound", isOn: $state.useAlarmSound)
                } header: { Text("Enable") }

                Section {
                    HStack {
                        Text("Low")
                        Spacer()
                        DecimalTextField("0", value: $state.lowGlucose, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("High")
                        Spacer()
                        DecimalTextField("0", value: $state.highGlucose, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Carbs Required Threshold")
                        Spacer()
                        DecimalTextField("0", value: $state.carbsRequiredThreshold, formatter: carbsFormatter)
                        Text("g").foregroundColor(.secondary)
                    }
                } header: { Text("Thresholds") }

                Section {
                    if !state.useAlarmSound {
                        Text("Disabled").foregroundStyle(.secondary)
                    } else {
                        soundPicker(
                            title: "Hypoglycemia",
                            selection: $state.hypoSound
                        )
                        soundPicker(
                            title: "Hyperglycemia",
                            selection: $state.hyperSound
                        )
                        soundPicker(
                            title: "Rapidly Ascending",
                            selection: $state.ascending
                        )
                        soundPicker(
                            title: "Rapidly Descending",
                            selection: $state.descending
                        )
                        soundPicker(
                            title: "Carbs Required",
                            selection: $state.carbSound
                        )
                        soundPicker(
                            title: "Bolus Failure",
                            selection: $state.bolusFailure
                        )
                        Picker(selection: $state.missingLoops, label: Text("Missing Loops")) {
                            silentView.tag(false)
                            Text("iOS default sound").tag(true)
                        }.pickerStyle(.navigationLink)
                    }
                } header: { Text("Sounds") }

                Section(
                    header: Text("Live Activity"),
                    footer: Text(liveActivityFooterText()),
                    content: {
                        if !systemLiveActivitySetting {
                            Button("Open Settings App") {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                        } else {
                            Toggle("Show Live Activity", isOn: $state.useLiveActivity)
                            if state.useLiveActivity {
                                Toggle("Display Chart", isOn: $state.liveActivityChart)
                                if state.liveActivityChart {
                                    Toggle("Show Predictions", isOn: $state.liveActivityChartShowPredictions)
                                }
                            }
                        }
                    }
                ).onReceive(resolver.resolve(LiveActivityBridge.self)!.$systemEnabled, perform: {
                    self.systemLiveActivitySetting = $0
                })
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationBarTitle("Notifications")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private func soundPicker(
            title: String,
            selection: Binding<String>
        ) -> some View {
            Picker(title, selection: selection) {
                silentView.tag(silent)
                defaultView.tag(defaultSound)
                ForEach(soundManager.infos, id: \.self.name) { i in
                    buttonView(name: i.name)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }
}
