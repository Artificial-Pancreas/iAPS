import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayGlucosePreference: DisplayGlucosePreference
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

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
            displayGlucosePreference = resolver.resolve(DisplayGlucosePreference.self)!
        }

        var body: some View {
            NavigationView {
                Form {
                    if let cgmManager = state.deviceManager.cgmManager as? CGMManagerUI
                    {
                        Section(header: Text("Active CGM")) {
                            HStack {
                                Text("Type")
                                Spacer()
                                Text(cgmManager.localizedTitle)
                            }
                        }
                        Section {
                            if let status = cgmManager.cgmStatusHighlight?.localizedMessage {
                                HStack {
                                    Text(status.replacingOccurrences(of: "\n", with: " ")).font(.caption)
                                }
                            }
                        }
                        Section {
                            Button("CGM Configuration") {
                                state.cgmIdentifierToSetUp = cgmManager.pluginIdentifier
                            }
                        }
                    } else if let pumpManager = state.deviceManager.cgmManager as? PumpManagerUI {
                        Section(header: Text("Active CGM")) {
                            HStack {
                                Text("Pump/CGM")
                                Spacer()
                                Text(pumpManager.localizedTitle)
                            }
                            Button("Stop using the pump as CGM") {
                                state.removePumpAsCGM()
                            }
                        }
                    } else if let appGroupSourceType = state.appGroupSourceType {
                        Section(header: Text("Shared App Group Source")) {
                            HStack {
                                Text("Reading from")
                                Spacer()
                                Text(appGroupSourceType.displayName)
                            }
                        }

                        if let link = appGroupSourceType.externalLink {
                            Button("About this source") {
                                UIApplication.shared.open(link, options: [:], completionHandler: nil)
                            }
                        }

                        Section(header: Text("Heartbeat")) {
                            VStack(alignment: .leading) {
                                if let cgmTransmitterDeviceAddress = state.cgmTransmitterDeviceAddress {
                                    Text("CGM address :")
                                    Text(cgmTransmitterDeviceAddress).font(.caption)
                                } else {
                                    Text("CGM is not used as heartbeat.")
                                }
                            }
                        }

                        Section {
                            HStack {
                                TextField("0", value: $state.sensorDays, formatter: daysFormatter)
                                Text("days").foregroundStyle(.secondary)
                            }
                        }
                        header: { Text("Sensor Life-Span") }
                        footer: {
                            Text(
                                "When using \(appGroupSourceType.displayName) iAPS doesn't know the type of sensor used or the sensor life-span."
                            )
                        }

                        Button(
                            NSLocalizedString("Disconnect", comment: "Disconnect from App Group Source button")
                        ) {
                            // TODO: better label?
                            state.appGroupSourceType = nil
                        }
                        .tint(.red)

                    } else {
                        Section(header: Text("Add CGM")) {
                            ForEach(state.deviceManager.availableCGMManagers, id: \.identifier) { cgm in
                                VStack(alignment: .leading) {
                                    Button(cgm.localizedTitle) {
                                        state.cgmIdentifierToSetUp = cgm.identifier
                                    }
                                }
                            }
                        }
                        Section(header: Text("Shared App Group Source")) { // TODO: better title?
                            Text("Read BG from an external CGM app using a shared app group.").font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(AppGroupSourceType.allCases) { type in
                                VStack(alignment: .leading) {
                                    Button(
                                        NSLocalizedString("Read from ", comment: "Read from App Group Source button") + type
                                            .displayName
                                    ) {
                                        state.appGroupSourceType = type
                                    }
                                }
                            }
                        }
                    }

                    if let cgmManager = state.deviceManager.cgmManager as? CGMManagerUI,
                       cgmManager.pluginIdentifier == KnownPlugins.Ids.libreTransmitter
                    {
                        Text("Calibrations").navigationLink(to: .calibrations, from: self)
                    }

                    Section(header: Text("Experimental")) {
                        Toggle("Smooth Glucose Value", isOn: $state.smoothGlucose)
                    }
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
                                displayGlucosePreference: displayGlucosePreference,
                                completionDelegate: state,
                                onboardingDelegate: state.deviceManager.cgmManagerOnboardingDelegate
                            )
                        } else {
                            CGMSetupView(
                                cgmIdentifier: identifier,
                                deviceManager: state.deviceManager,
                                completionDelegate: state,
                                onboardingDelegate: state.deviceManager.cgmManagerOnboardingDelegate
                            )
                        }
                    }
                }
            }
        }
    }
}
