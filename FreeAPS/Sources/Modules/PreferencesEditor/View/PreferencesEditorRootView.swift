import SwiftUI

struct InfoText: Identifiable {
    var id: String { description }
    let description: String
    let oref0Variable: String
}

extension PreferencesEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        @State private var infoButtonPressed: InfoText?

        var body: some View {
            Form {
                Section(header: Text("FreeAPS X")) {
                    Picker("Glucose units", selection: $viewModel.unitsIndex) {
                        Text("mg/dL").tag(0)
                        Text("mmol/L").tag(1)
                    }

                    Toggle("Remote control", isOn: $viewModel.allowAnnouncements)

                    HStack {
                        Text("Recommended Insulin Fraction")
                        DecimalTextField("", value: $viewModel.insulinReqFraction, formatter: formatter)
                    }

                    Toggle("Skip Bolus screen after carbs", isOn: $viewModel.skipBolusScreenAfterCarbs)
                }

                Section(header: Text("OpenAPS")) {
                    Picker(selection: $viewModel.insulinCurveField.value, label: Text(viewModel.insulinCurveField.displayName)) {
                        ForEach(InsulinCurve.allCases) { v in
                            Text(v.rawValue).tag(v)
                        }
                    }

                    ForEach(viewModel.boolFields.indexed(), id: \.1.id) { index, field in
                        HStack {
                            Button("", action: {
                                infoButtonPressed = InfoText(description: field.infoText, oref0Variable: field.displayName)
                            })
                            Toggle(field.displayName, isOn: self.$viewModel.boolFields[index].value)
                        }
                    }

                    ForEach(viewModel.decimalFields.indexed(), id: \.1.id) { index, field in
                        HStack {
                            Button("", action: {
                                infoButtonPressed = InfoText(description: field.infoText, oref0Variable: field.displayName)
                            })
                            Text(field.displayName)
                            DecimalTextField("0", value: self.$viewModel.decimalFields[index].value, formatter: formatter)
                        }
                    }
                }
                Section {
                    Text("Edit settings json").chevronCell()
                        .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(item: $infoButtonPressed) { infoButton in
                Alert(
                    title: Text("\(infoButton.oref0Variable)"),
                    message: Text("\(infoButton.description)"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}
