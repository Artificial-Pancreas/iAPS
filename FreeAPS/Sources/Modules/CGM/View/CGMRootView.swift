import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var setupCGM = false

        // @AppStorage(UserDefaults.BTKey.cgmTransmitterDeviceAddress.rawValue) private var cgmTransmitterDeviceAddress: String? = nil

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("CGM")) {
                        Picker("Type", selection: $state.cgm) {
                            ForEach(CGMType.allCases) { type in
                                VStack(alignment: .leading) {
                                    Text(type.displayName)
                                    Text(type.subtitle).font(.caption).foregroundColor(.secondary)
                                }.tag(type)
                            }
                        }
                        if let link = state.cgm.externalLink {
                            Button("About this source") {
                                UIApplication.shared.open(link, options: [:], completionHandler: nil)
                            }
                        }
                    }
                    if [.dexcomG5, .dexcomG6, .dexcomG7].contains(state.cgm) {
                        Section {
                            Button("CGM Configuration") {
                                setupCGM.toggle()
                            }
                        }
                    }
                    if state.cgm == .xdrip {
                        Section(header: Text("Heartbeat")) {
                            VStack(alignment: .leading) {
                                if let cgmTransmitterDeviceAddress = state.cgmTransmitterDeviceAddress {
                                    Text("CGM address :")
                                    Text(cgmTransmitterDeviceAddress)
                                } else {
                                    Text("CGM is not used as heartbeat.")
                                }
                            }
                        }
                    }
                    if state.cgm == .libreTransmitter {
                        Button("Configure Libre Transmitter") {
                            state.showModal(for: .libreConfig)
                        }
                        Text("Calibrations").navigationLink(to: .calibrations, from: self)
                    }
                    Section(header: Text("Calendar")) {
                        Toggle("Create Events in Calendar", isOn: $state.createCalendarEvents)
                        if state.calendarIDs.isNotEmpty {
                            Picker("Calendar", selection: $state.currentCalendarID) {
                                ForEach(state.calendarIDs, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                            Toggle("Display Emojis as Labels", isOn: $state.displayCalendarEmojis)
                            Toggle("Display IOB and COB", isOn: $state.displayCalendarIOBandCOB)
                        } else if state.createCalendarEvents {
                            if #available(iOS 17.0, *) {
                                Text(
                                    "If you are not seeing calendars to choose here, please go to Settings -> iAPS -> Calendars and change permissions to \"Full Access\""
                                ).font(.footnote)

                                Button("Open Settings") {
                                    // Get the settings URL and open it
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Toggle("Smooth Glucose Value", isOn: $state.smoothGlucose)

                        if state.smoothGlucose {
                            Picker("Toggle it off in", selection: $state.schedule) {
                                Text("24 hours").tag(SmoothingSchedule.oneDays)
                                Text("Two days").tag(SmoothingSchedule.twoDays)
                                Text("Never").tag(SmoothingSchedule.never)
                            }._onBindingChange($state.schedule) { schedule in
                                switch schedule {
                                case .oneDays:
                                    state.smoothGlucoseScheduleIsOn = true
                                    state.smoothGlucose24 = Date.now.addingTimeInterval(24.hours.timeInterval)
                                case .twoDays:
                                    state.smoothGlucoseScheduleIsOn = true
                                    state.smoothGlucose24 = Date.now.addingTimeInterval(2.days.timeInterval)
                                case .never:
                                    state.smoothGlucoseScheduleIsOn = false
                                }
                            }
                        }
                    }
                    header: { Text("Smooth Glucose Value") }
                    footer: {
                        (
                            state
                                .schedule != .never && state.smoothGlucose
                        ) ?
                            Text(
                                NSLocalizedString("Countdown hours: ", comment: "Hours left of CGM smoothing") + (
                                    formatter
                                        .string(from: abs(state.smoothGlucose24.timeIntervalSinceNow / 3600) as NSNumber) ?? ""
                                )
                            ).frame(maxWidth: .infinity, alignment: .trailing) :
                            nil
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .onAppear {
                    configureView()
                    fetchCurrentSchedule()
                }
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $setupCGM) {
                    if let cgmFetchManager = state.cgmManager, cgmFetchManager.glucoseSource.cgmType == state.cgm,
                       let cmgManager = cgmFetchManager.glucoseSource.cgmManager
                    {
                        CGMSettingsView(
                            cgmManager: cmgManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state
                        )
                    } else {
                        CGMSetupView(
                            CGMType: state.cgm,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    }
                }
                .onChange(of: setupCGM) { setupCGM in
                    state.setupCGM = setupCGM
                }
                .onChange(of: state.setupCGM) { setupCGM in
                    self.setupCGM = setupCGM
                }
                .onChange(of: state.smoothGlucose) { smoothing in
                    if !smoothing { state.schedule = .never }
                }
            }
        }

        private func fetchCurrentSchedule() {
            if state.smoothGlucose, state.smoothGlucoseScheduleIsOn, state.smoothGlucose24 <= Date.now {
                state.smoothGlucose = false
                state.schedule = .never
            }
        }
    }
}
