import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var setupCGM = false

        private var daysFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        // @AppStorage(UserDefaults.BTKey.cgmTransmitterDeviceAddress.rawValue) private var cgmTransmitterDeviceAddress: String? = nil

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

                    if state.cgm == .xdrip || state.cgm == .glucoseDirect {
                        Section {
                            HStack {
                                TextField("0", value: $state.sensorDays, formatter: daysFormatter)
                                Text("days").foregroundStyle(.secondary)
                            }
                        }
                        header: { Text("Sensor Life-Span") }
                        footer: {
                            Text(
                                "When using \(state.cgm.rawValue) iAPS doesn't know the type of sensor used or the sensor life-span."
                            )
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

                    Section(header: Text("Experimental")) {
                        Toggle("Smooth Glucose Value", isOn: $state.smoothGlucose)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .onAppear(perform: configureView)
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
                .onChange(of: setupCGM) {
                    state.setupCGM = setupCGM
                }
                .onChange(of: state.setupCGM) {
                    self.setupCGM = state.setupCGM
                }
            }
        }
    }
}
