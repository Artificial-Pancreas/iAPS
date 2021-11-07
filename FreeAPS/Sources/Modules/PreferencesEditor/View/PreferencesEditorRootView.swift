import SwiftUI
import Swinject

struct InfoText: Identifiable {
    var id: String { description }
    let description: String
    let oref0Variable: String
}

extension PreferencesEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        @State private var infoButtonPressed: InfoText?

        var body: some View {
            Form {
                Section(header: Text("FreeAPS X")) {
                    Picker("Glucose units", selection: $state.unitsIndex) {
                        Text("mg/dL").tag(0)
                        Text("mmol/L").tag(1)
                    }

                    Toggle("Remote control", isOn: $state.allowAnnouncements)

                    HStack {
                        Text("Recommended Insulin Fraction")
                        DecimalTextField("", value: $state.insulinReqFraction, formatter: formatter)
                    }

                    Toggle("Skip Bolus screen after carbs", isOn: $state.skipBolusScreenAfterCarbs)
                }

                Section(header: Text("OpenAPS")) {
                    Picker(selection: $state.insulinCurveField.value, label: Text(state.insulinCurveField.displayName)) {
                        ForEach(InsulinCurve.allCases) { v in
                            Text(v.rawValue).tag(v)
                        }
                    }

                    ForEach(state.boolFields.indexed(), id: \.1.id) { index, field in
                        HStack {
                            Button("", action: {
                                infoButtonPressed = InfoText(description: field.infoText, oref0Variable: field.displayName)
                            })
                            Toggle(field.displayName, isOn: self.$state.boolFields[index].value)
                        }
                    }

                    ForEach(state.decimalFields.indexed(), id: \.1.id) { index, field in
                        HStack {
                            Button("", action: {
                                infoButtonPressed = InfoText(description: field.infoText, oref0Variable: field.displayName)
                            })
                            Text(field.displayName)
                            DecimalTextField("0", value: self.$state.decimalFields[index].value, formatter: formatter)
                        }
                    }
                }
                Section {
                    Text("Edit settings json")
                        .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
                }
            }
            .onAppear(perform: configureView)
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
