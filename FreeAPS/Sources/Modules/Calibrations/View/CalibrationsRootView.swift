import SwiftUI
import Swinject

extension Calibrations {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var isPromtPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Add calibration")) {
                    HStack {
                        Text("Meter glucose")
                        Spacer()
                        DecimalTextField("0", value: $state.calibration, formatter: formatter, autofocus: false, cleanInput: true)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    Button {
                        state.addCalibration()
                    }
                    label: { Text("Add") }
                        .disabled(state.calibration <= 0)
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
                        .disabled(state.calibrationsCount == 0)

                    Button {
                        state.removeAll()
                    }
                    label: { Text("Remove All") }
                        .disabled(state.calibrationsCount == 0)
                }
            }
            .popover(isPresented: $isPromtPresented) {
                Form {}
            }
            .onAppear(perform: configureView)
            .navigationTitle("Calibrations")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
