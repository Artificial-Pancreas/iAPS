import SwiftUI
import Swinject

extension CGM {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section {
                    Picker("Type", selection: $state.cgm) {
                        ForEach(CGMType.allCases) { type in
                            VStack(alignment: .leading) {
                                Text(type.displayName)
                                Text(type.subtitle).font(.caption).foregroundColor(.secondary)
                            }.tag(type)
                        }
                    }
                    if let link = state.cgm.externalLink {
                        Button("About this source") {
                            UIApplication.shared.open(link, options: [:], completionHandler: nil)
                        }
                    }
                }
                if [.dexcomG5, .dexcomG6].contains(state.cgm) {
                    Section(header: Text("Transmitter ID")) {
                        TextField("XXXXXX", text: $state.transmitterID, onCommit: {
                            UIApplication.shared.endEditing()
                            state.onChangeID()
                        })
                            .disableAutocorrection(true)
                            .autocapitalization(.allCharacters)
                            .keyboardType(.asciiCapable)
                    }
                    .onDisappear {
                        state.onChangeID()
                    }
                }

                if state.cgm == .libreTransmitter {
                    Button("Configure Libre Transmitter") {
                        state.showModal(for: .libreConfig)
                    }
                    Text("Calibrations").navigationLink(to: .calibrations, from: self)
                }

                Section(header: Text("Calendar")) {
                    Toggle("Create events in calendar", isOn: $state.createCalendarEvents)
                    if state.calendarIDs.isNotEmpty {
                        Picker("Calendar", selection: $state.currentCalendarID) {
                            ForEach(state.calendarIDs, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                    }
                }

                Section(header: Text("Other")) {
                    Toggle("Upload glucose to Nightscout", isOn: $state.uploadGlucose)
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("CGM")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
