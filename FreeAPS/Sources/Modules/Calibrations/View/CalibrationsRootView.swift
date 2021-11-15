import SwiftUI
import Swinject

extension Calibrations {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            GeometryReader { geo in
                Form {
                    Section(header: Text("Add calibration")) {
                        HStack {
                            Text("Meter glucose")
                            Spacer()
                            DecimalTextField(
                                "0",
                                value: $state.newCalibration,
                                formatter: formatter,
                                autofocus: false,
                                cleanInput: true
                            )
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }
                        Button {
                            state.addCalibration()
                        }
                        label: { Text("Add") }
                            .disabled(state.newCalibration <= 0)
                    }

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
                    }

                    Section(header: Text("Remove")) {
                        Button {
                            state.removeLast()
                        }
                        label: { Text("Remove Last") }
                            .disabled(state.calibrations.isEmpty)

                        Button {
                            state.removeAll()
                        }
                        label: { Text("Remove All") }
                            .disabled(state.calibrations.isEmpty)
                    }

                    Section(header: Text("Chart")) {
                        CalibrationsChart().environmentObject(state)
                            .frame(minHeight: geo.size.width)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Calibrations")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
