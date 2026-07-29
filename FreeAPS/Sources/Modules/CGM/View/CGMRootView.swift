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

        private var smoothingSection: some View {
            let selected = state.glucoseSmoothing.algorithm
            return Section {
                settingRow(description: selected.settingsDescription) {
                    Picker("Algorithm", selection: $state.glucoseSmoothing.algorithm) {
                        ForEach(GlucoseSmoothingAlgorithm.allCases) { algorithm in
                            Text(algorithm.displayName).tag(algorithm)
                        }
                    }
                }

                switch selected {
                case .off:
                    EmptyView()
                case .savitzkyGolay:
                    settingRow(description: selected.optionsDescription) {
                        Picker("Passes", selection: $state.glucoseSmoothing.savitzkyGolay.passes) {
                            ForEach(SavitzkyGolayPasses.allCases) { passes in
                                Text(passes.displayName).tag(passes)
                            }
                        }
                    }
                case .kalman:
                    settingRow(description: selected.optionsDescription) {
                        Picker("Responsiveness", selection: $state.glucoseSmoothing.kalman.responsiveness) {
                            ForEach(KalmanResponsiveness.allCases) { responsiveness in
                                Text(responsiveness.displayName).tag(responsiveness)
                            }
                        }
                    }
                }
            }
            header: { Text("Smoothing") }
        }

        private func settingRow(description: String?, @ViewBuilder control: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                control()
                    .pickerStyle(.menu)
                if let description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
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

                    if let cgmInfo, cgmInfo.isOnboarded
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

                        smoothingSection
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
