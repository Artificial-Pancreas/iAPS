import SwiftUI
import Swinject

extension Calibrations {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        private let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        private var glucoseFormatter: NumberFormatter {
            state.units == .mmolL ? glucoseFormatterMmol : glucoseFormatterMgdl
        }

        private let glucoseFormatterMmol: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }()

        private let glucoseFormatterMgdl: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }()

        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .short
            return formatter
        }()

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            GeometryReader { geo in
                Form {
                    addCalibrationSection()

                    Section(header: Text("Info")) {
                        HStack {
                            Text("Slope")
                            Spacer()
                            Text(formatter.string(from: state.slope as NSNumber)!)
                        }
                        HStack {
                            Text("Intercept")
                            Spacer()
                            Text(formatter.string(from: state.intercept as NSNumber)!)
                        }

                        if let explanation = state.spreadExplanation {
                            Label(explanation, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    fitSection()

                    Section {
                        Button {
                            state.recalibrateHistory()
                        } label: {
                            HStack {
                                Text("Recalculate stored readings")
                                if state.isUpdatingHistory {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(state.calibrations.isEmpty || state.isUpdatingHistory)

                        if let message = state.historyMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Stored readings")
                    } footer: {
                        Text(
                            "Applies the current slope and intercept to the readings already stored for this sensor session (last 24 hours)."
                        )
                    }

                    Section {
                        Button {
                            state.removeLast()
                        }
                        label: { Text("Remove Last") }
                            .disabled(state.calibrations.isEmpty || state.isUpdatingHistory)

                        Button {
                            state.removeAll()
                        }
                        label: { Text("Remove All") }
                            .disabled(state.calibrations.isEmpty || state.isUpdatingHistory)

                        Button {
                            state.removeAllAndResetHistory()
                        }
                        label: { Text("Remove All and reset history") }
                            .disabled(state.calibrations.isEmpty || state.isUpdatingHistory)
                        List {
                            ForEach(state.items) { item in
                                HStack {
                                    Text(dateFormatter.string(from: item.calibration.date))
                                    Spacer()
                                    VStack(alignment: .leading) {
                                        Text("raw: \(item.calibration.x)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("value: \(item.calibration.y)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .onDelete(perform: delete)
                            .deleteDisabled(state.isUpdatingHistory)
                        }
                    } header: {
                        Text("Remove")
                    } footer: {
                        Text(
                            "\"Remove All and reset history\" also restores the stored readings of this sensor session to the sensor's raw, uncalibrated values."
                        )
                    }

                    if state.calibrations.isNotEmpty {
                        Section(header: Text("Chart")) {
                            CalibrationsChart().environmentObject(state)
                                .frame(minHeight: geo.size.width)
                        }
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Calibrations")
            .navigationBarItems(
                trailing: EditButton().disabled(state.calibrations.isEmpty || state.isUpdatingHistory)
            )
            .navigationBarTitleDisplayMode(.automatic)
        }

        @ViewBuilder private func fitSection() -> some View {
            Section {
                Toggle("Robust fit", isOn: $state.robustFit)
                    .disabled(!state.canUseRobustFit || state.isUpdatingHistory)
            } header: {
                Text("Fit")
            } footer: {
                Text(
                    "Takes the slope from the middle of the slopes through every pair of calibrations, instead of the line that best fits all of them at once. One calibration taken at a bad moment is then outvoted rather than dragging the whole correction with it. Needs at least three calibrations."
                )
            }

            if state.showRelaxLimits {
                Section {
                    Toggle("Allow a wider correction", isOn: $state.relaxLimits)
                        .disabled(state.isUpdatingHistory)

                    if let explanation = state.limitExplanation {
                        Label(explanation, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text(
                        "The slope is normally held between 0.80 and 1.25 and the offset within ±100 mg/dL, which is what stops a thin or badly timed set of calibrations from making the readings worse. This widens them to 0.50–2.00 and ±200 mg/dL. Turn it on only when the calibrations are ones you trust: several, taken at different glucose levels, with the glucose flat each time."
                    )
                }
            }
        }

        @ViewBuilder private func addCalibrationSection() -> some View {
            let paired = state.pairedReading

            Section(header: Text("Add calibration")) {
                HStack {
                    Text("Meter glucose")
                    Spacer()
                    DecimalTextField(
                        "0",
                        value: $state.newCalibration,
                        formatter: formatter,
                        autofocus: false,
                        liveEditing: true
                    )
                    Text(state.units.rawValue).foregroundColor(.secondary)
                }

                Toggle("Entered at a past time", isOn: $state.useCustomDate)

                if state.useCustomDate {
                    DatePicker("Time", selection: $state.calibrationDate, in: state.dateRange)
                }

                if let resolved = try? paired.get() {
                    HStack {
                        Text("Sensor reading")
                        Spacer()
                        Text(sensorValueText(resolved.uncalibrated))
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    if !resolved.isStable {
                        Label(
                            NSLocalizedString(
                                "Glucose was moving quickly then. A calibration taken while the sensor is still catching up will skew the correction — prefer a flat reading.",
                                comment: "Calibration stability warning"
                            ),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }
                }

                if let message = errorMessage(paired) {
                    Label(message, systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button {
                    state.addCalibration()
                }
                label: { Text("Add") }
                    .disabled(
                        state.newCalibration <= 0 || (try? paired.get()) == nil || state.isUpdatingHistory
                    )
            }
            .onChange(of: state.newCalibration) { state.error = nil }
            .onChange(of: state.useCustomDate) { state.error = nil }
            .onChange(of: state.calibrationDate) { state.error = nil }
        }

        private func errorMessage(_ paired: Result<PairedReading, LookupError>) -> String? {
            if let error = state.error {
                return error.message
            }
            if case let .failure(lookupError) = paired {
                return lookupError.message
            }
            return nil
        }

        private func sensorValueText(_ mgdl: Double) -> String {
            let value = state.units == .mmolL ? mgdl.asMmolL : Decimal(mgdl)
            return glucoseFormatter.string(from: value as NSNumber) ?? "--"
        }

        private func delete(at offsets: IndexSet) {
            state.removeAtIndex(offsets[offsets.startIndex])
        }
    }
}
