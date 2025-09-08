import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        private var isCGMSetupPresented: Binding<Bool> {
            Binding<Bool>(
                get: { state.cgmIdentifierToSetUp != nil },
                set: { if !$0 { state.cgmIdentifierToSetUp = nil } }
            )
        }

        private var daysFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        // @AppStorage(UserDefaults.BTKey.cgmTransmitterDeviceAddress.rawValue) private var cgmTransmitterDeviceAddress: String? = nil

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("CGM")) {
                        if let cgmManager = state.deviceManager.cgmManager as? CGMManagerUI
                        {
                            HStack {
                                Text("Type").font(.caption)
                                Spacer()
                                Text(cgmManager.localizedTitle)
                            }
                            if let status = cgmManager.cgmStatusHighlight?.localizedMessage {
                                HStack {
                                    Text(status.replacingOccurrences(of: "\n", with: " ")).font(.caption)
                                }
                            }
                            Button("Configure CGM") {
                                state.cgmIdentifierToSetUp = cgmManager.pluginIdentifier
                            }

                        } else {
                            ForEach(state.deviceManager.availableCGMManagers, id: \.identifier) { cgm in
                                VStack(alignment: .leading) {
                                    Button(cgm.localizedTitle) {
                                        state.cgmIdentifierToSetUp = cgm.identifier
                                        //                                        state.createCGM(identifier: cgm.identifier)
                                        //                                            state.deviceManager.setupCGMManager(withIdentifier: cgm.identifier, prefersToSkipUserInteraction: false)
                                    }
                                }
                            }

                            //                        if let link = state.cgm.externalLink {
                            //                            Button("About this source") {
                            //                                UIApplication.shared.open(link, options: [:], completionHandler: nil)
                            //                            }
                            //                        }
                        }
                    }

//                    if [.dexcomG5, .dexcomG6, .dexcomG7].contains(state.cgm) {
//                        Section {
//                            Button("CGM Configuration") {
//                                setupCGM.toggle()
//                            }
//                        }
//                    }
//                    if state.cgm == .xdrip {
//                        Section(header: Text("Heartbeat")) {
//                            VStack(alignment: .leading) {
//                                if let cgmTransmitterDeviceAddress = state.cgmTransmitterDeviceAddress {
//                                    Text("CGM address :")
//                                    Text(cgmTransmitterDeviceAddress)
//                                } else {
//                                    Text("CGM is not used as heartbeat.")
//                                }
//                            }
//                        }
//                    }
//
//                    if state.cgm == .xdrip || state.cgm == .glucoseDirect {
//                        Section {
//                            HStack {
//                                TextField("0", value: $state.sensorDays, formatter: daysFormatter)
//                                Text("days").foregroundStyle(.secondary)
//                            }
//                        }
//                        header: { Text("Sensor Life-Span") }
//                        footer: {
//                            Text(
//                                "When using \(state.cgm.rawValue) iAPS doesn't know the type of sensor used or the sensor life-span."
//                            )
//                        }
//                    }
//
//                    if state.cgm == .libreTransmitter {
//                        Button("Configure Libre Transmitter") {
//                            state.showModal(for: .libreConfig)
//                        }
//                        Text("Calibrations").navigationLink(to: .calibrations, from: self)
//                    }
//                    Section(header: Text("Calendar")) {
//                        Toggle("Create Events in Calendar", isOn: $state.createCalendarEvents)
//                        if state.calendarIDs.isNotEmpty {
//                            Picker("Calendar", selection: $state.currentCalendarID) {
//                                ForEach(state.calendarIDs, id: \.self) {
//                                    Text($0).tag($0)
//                                }
//                            }
//                            Toggle("Display Emojis as Labels", isOn: $state.displayCalendarEmojis)
//                            Toggle("Display IOB and COB", isOn: $state.displayCalendarIOBandCOB)
//                        } else if state.createCalendarEvents {
//                            Text(
//                                "If you are not seeing calendars to choose here, please go to Settings -> iAPS -> Calendars and change permissions to \"Full Access\""
//                            ).font(.footnote)
//
//                            Button("Open Settings") {
//                                // Get the settings URL and open it
//                                if let url = URL(string: UIApplication.openSettingsURLString) {
//                                    UIApplication.shared.open(url)
//                                }
//                            }
//                        }
//                    }

//                    Section(header: Text("Experimental")) {
//                        Toggle("Smooth Glucose Value", isOn: $state.smoothGlucose)
//                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: isCGMSetupPresented) {
                    if let identifier = state.cgmIdentifierToSetUp {
                        if let cgmManager = state.deviceManager.cgmManager as? CGMManagerUI,
                           cgmManager.pluginIdentifier == identifier
                        {
                            CGMSettingsView(
                                cgmManager: cgmManager,
                                bluetoothManager: state.provider.apsManager.bluetoothManager!,
                                unit: state.settingsManager.settings.units,
                                completionDelegate: state,
                                onboardingDelegate: state.deviceManager
                            )
                        } else {
                            CGMSetupView(
                                cgmIdentifier: identifier,
                                deviceManager: state.deviceManager,
                                completionDelegate: state,
                                onboardingDelegate: state.deviceManager
                            )
                        }
                    }
                }
            }
        }
    }
}
