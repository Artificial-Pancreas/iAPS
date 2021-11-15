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
                        ForEach(CGMType.allCases) {
                            Text($0.displayName).tag($0)
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
