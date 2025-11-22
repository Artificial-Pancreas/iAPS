import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayGlucosePreference: DisplayGlucosePreference
        @StateObject var state: StateModel

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
                    if let cgmManager = state.deviceManager.cgmManager as? CGMManagerUI,
                       cgmManager.isOnboarded
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
                                    Text(status.replacingOccurrences(of: "\n", with: " "))
                                }
                            }
                            if !cgmManager.providesBLEHeartbeat {
                                HStack {
                                    Text("CGM is not used as heartbeat.")
                                }
                            }
                        }
                        Section {
                            Button("CGM Configuration") {
                                state.setupCGM(cgmManager.pluginIdentifier)
                            }
                        }
                    } else if let pumpManager = state.deviceManager.cgmManager as? PumpManagerUI {
                        Section(header: Text("Active CGM")) {
                            HStack {
                                Text("Pump+CGM")
                                Spacer()
                                Text(pumpManager.localizedTitle)
                            }
                            Button("Stop using the pump as CGM") {
                                state.removePumpAsCGM()
                            }
                        }
                    } else {
                        Section {
                            ForEach(state.deviceManager.availableCGMManagers, id: \.identifier) { cgm in
                                VStack(alignment: .leading) {
                                    Button(cgm.localizedTitle) {
                                        state.setupCGM(cgm.identifier)
                                    }
                                }
                            }
                        }
                        header: {
                            Text("Connect to CGM")
                        }
                        footer: {
                            Text(
                                "To receive reading from xDrip4iOS, Glucose Direct or another compatible app, select Shared App Group CGM."
                            )
                            .font(.caption)
                        }
                    }

                    if let cgmManager = state.deviceManager.cgmManager,
                       cgmManager.isOnboarded
                    {
                        if KnownPlugins.allowCalibrations(for: cgmManager)
                        {
                            Text("Calibrations").navigationLink(to: .calibrations, from: self)
                        }

                        // if CGM/App is selected but sensor life-span is not known...
                        if KnownPlugins.cgmExpirationByPluginIdentifier(state.deviceManager.cgmManager) == nil
                        {
                            Section {
                                HStack {
                                    TextField("0", value: $state.sensorDays, formatter: daysFormatter)
                                    Text("days").foregroundStyle(.secondary)
                                }
                            }
                            header: { Text("Sensor Life-Span") }
                            footer: {
                                Text(
                                    "When using \(cgmManager.localizedTitle) iAPS doesn't know the type of sensor used or the sensor life-span."
                                )
                            }
                        }

                        Section(header: Text("Experimental")) {
                            Toggle("Smooth Glucose Value", isOn: $state.smoothGlucose)
                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle("CGM")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $state.cgmSetupPresented) {
                    if let identifier = state.cgmIdentifierToSetUp {
                        CGMSetupView(
                            cgmIdentifier: identifier,
                            deviceManager: state.deviceManager,
                            completionDelegate: state,
                        )
                    }
                }
                .sheet(isPresented: $state.cgmSettingsPresented) {
                    if let identifier = state.cgmIdentifierToSetUp,
                       let cgmManager = state.deviceManager.cgmManager as? CGMManagerUI,
                       cgmManager.pluginIdentifier == identifier
                    {
                        CGMSettingsView(
                            cgmManager: cgmManager,
                            deviceManager: state.deviceManager,
                            completionDelegate: state,
                        )
                    }
                }
            }
        }
    }
}
