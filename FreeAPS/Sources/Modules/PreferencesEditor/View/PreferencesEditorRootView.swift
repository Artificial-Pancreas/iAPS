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
                Section {
                    Picker("Glucose units", selection: $state.unitsIndex) {
                        Text("mg/dL").tag(0)
                        Text("mmol/L").tag(1)
                    }
                } header: { Text("iAPS").textCase(nil) }
                ForEach(state.sections.indexed(), id: \.1.id) { sectionIndex, section in
                    Section(header: Text(section.displayName)) {
                        ForEach(section.fields.indexed(), id: \.1.id) { fieldIndex, field in
                            HStack {
                                switch field.type {
                                case .boolean:
                                    ZStack {
                                        Button("", action: {
                                            infoButtonPressed = InfoText(
                                                description: field.infoText,
                                                oref0Variable: field.displayName
                                            )
                                        })
                                        Toggle(isOn: self.$state.sections[sectionIndex].fields[fieldIndex].boolValue) {
                                            Text(field.displayName)
                                        }
                                    }
                                case .decimal:
                                    ZStack {
                                        Button("", action: {
                                            infoButtonPressed = InfoText(
                                                description: field.infoText,
                                                oref0Variable: field.displayName
                                            )
                                        })
                                        Text(field.displayName)
                                    }
                                    DecimalTextField(
                                        "0",
                                        value: self.$state.sections[sectionIndex].fields[fieldIndex].decimalValue,
                                        formatter: formatter
                                    )
                                case .glucose:
                                    ZStack {
                                        Button("", action: {
                                            infoButtonPressed = InfoText(
                                                description: field.infoText,
                                                oref0Variable: field.displayName
                                            )
                                        })
                                        Text(field.displayName)
                                    }
                                    BGTextField(
                                        "0",
                                        mgdlValue: self.$state.sections[sectionIndex].fields[fieldIndex].decimalValue,
                                        units: Binding(
                                            get: { self.state.unitsIndex == 0 ? .mgdL : .mmolL },
                                            set: { _ in }
                                        ),
                                        isDisabled: false
                                    )
                                case .insulinCurve:
                                    Picker(
                                        selection: $state.sections[sectionIndex].fields[fieldIndex].insulinCurveValue,
                                        label: Text(field.displayName)
                                    ) {
                                        ForEach(InsulinCurve.allCases) { v in
                                            Text(v.rawValue).tag(v)
                                        }
                                    }
                                }
                            }

                            // Exceptions. Below a FreeAPS setting added.
                            if field.displayName == NSLocalizedString("Max COB", comment: "Max COB") {
                                maxCarbs
                            }
                        }
                    }
                }
                Section {} footer: { Text("").padding(.bottom, 300) }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                trailing:
                Button {
                    let lang = Locale.current.language.languageCode?.identifier ?? "en"
                    if lang == "en" {
                        UIApplication.shared.open(
                            URL(
                                string: "https://openaps.readthedocs.io/en/latest/docs/While%20You%20Wait%20For%20Gear/preferences-and-safety-settings.html"
                            )!,
                            options: [:],
                            completionHandler: nil
                        )
                    } else {
                        UIApplication.shared.open(
                            URL(
                                string: "https://openaps-readthedocs-io.translate.goog/en/latest/docs/While%20You%20Wait%20For%20Gear/preferences-and-safety-settings.html?_x_tr_sl=en&_x_tr_tl=\(lang)&_x_tr_hl=\(lang)"
                            )!,
                            options: [:],
                            completionHandler: nil
                        )
                    }
                }
                label: { Image(systemName: "questionmark.circle") }
            )
            .alert(item: $infoButtonPressed) { infoButton in
                Alert(
                    title: Text("\(infoButton.oref0Variable)"),
                    message: Text("\(infoButton.description)"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }

        var maxCarbs: some View {
            HStack {
                ZStack {
                    Button("", action: {
                        infoButtonPressed = InfoText(
                            description: NSLocalizedString(
                                "Maximum amount of carbs (g) you can add each entry",
                                comment: "Max carbs description"
                            ),
                            oref0Variable: NSLocalizedString("Max Carbs", comment: "Max setting")
                        )
                    })
                    Text("Max Carbs")
                }
                DecimalTextField(
                    "0",
                    value: self.$state.maxCarbs,
                    formatter: formatter
                )
            }
        }
    }
}
