import LoopKitUI
import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state: StateModel

        @Environment(AppUIState.self) private var appUIState

        private var daysFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            let cgmInfo = appUIState.cgmInfo
            let cgmStatus = appUIState.cgmStatus
            NavigationView {
                Form {
                    if let cgmInfo = cgmInfo, cgmInfo.isOnboarded, !cgmInfo.pumpIsCgm
                    {
                        Section(header: Text("Active CGM")) {
                            HStack {
                                Text("Type")
                                Spacer()
                                Text(cgmInfo.name)
                            }
                        }
                        Section {
                            if let status = cgmStatus?.statusHighlight {
                                HStack {
                                    Text(status.replacingOccurrences(of: "\n", with: " "))
                                }
                            }
                            if !cgmInfo.providesHeartbeat {
                                HStack {
                                    Text("CGM is not used as heartbeat.")
                                }
                            }
                        }
                        Section {
                            Button("CGM Configuration") {
                                state.showCurrentCgmSettings()
                            }
                        }
                    } else if let cgmInfo = cgmInfo, cgmInfo.pumpIsCgm {
                        Section(header: Text("Active CGM")) {
                            HStack {
                                Text("Pump+CGM")
                                Spacer()
                                Text(cgmInfo.name)
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
                                        state.setupNewCgm(cgm.identifier)
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

                    if let cgmInfo = cgmInfo, cgmInfo.isOnboarded
                    {
                        if cgmInfo.allowCalibrations
                        {
                            Text("Calibrations").navigationLink(to: .calibrations, from: self)
                        }

                        // if CGM/App is selected but sensor life-span is not known...
                        if cgmInfo.sensorDays == nil
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
                                    "When using \(cgmInfo.name) iAPS doesn't know the type of sensor used or the sensor life-span."
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
                    CGMSettingsView(
                        deviceManager: state.deviceManager,
                        completionDelegate: state,
                    )
                }
            }
        }
    }
}
