import SwiftUI

struct DescriptionString: Identifiable {
    var id: String { name }
    let name: String
    let nameOfVariable: String
}

extension PreferencesEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        @State private var infoButtonPressed: DescriptionString?

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
                            Button("ⓘ", action: {
                                infoButtonPressed = DescriptionString(name: field.infoText, nameOfVariable: field.displayName)
                            })
                            Toggle(field.displayName, isOn: self.$viewModel.boolFields[index].value)
                        }
                    }
                    .alert(item: $infoButtonPressed) { iButton in
                        Alert(
                            title: Text(iButton.nameOfVariable),
                            message: Text(iButton.name),
                            dismissButton: .default(Text("Got it!"))
                        )
                    }

                    ForEach(viewModel.decimalFields.indexed(), id: \.1.id) { index, field in
                        HStack {
                            Button("ⓘ", action: {
                                infoButtonPressed = DescriptionString(name: field.infoText, nameOfVariable: field.displayName)
                            })
                            Text(field.displayName)
                            DecimalTextField("0", value: self.$viewModel.decimalFields[index].value, formatter: formatter)
                        }
                    }
                    .alert(item: $infoButtonPressed) { iButton in
                        Alert(
                            title: Text(iButton.nameOfVariable),
                            message: Text(iButton.name),
                            dismissButton: .default(Text("Got it!"))
                        )
                    }
                }

                Section {
                    Text("Edit settings json").chevronCell()
                        .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
