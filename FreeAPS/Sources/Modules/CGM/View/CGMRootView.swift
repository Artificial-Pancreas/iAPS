import SwiftUI

extension CGM {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section {
                    Picker("Type", selection: $viewModel.cgm) {
                        ForEach(CGMType.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
                if [.dexcomG5, .dexcomG6].contains(viewModel.cgm) {
                    Section(header: Text("Transmitter ID")) {
                        TextField("XXXXXX", text: $viewModel.transmitterID, onCommit: {
                            UIApplication.shared.endEditing()
                            viewModel.onChangeID()
                        })
                            .disableAutocorrection(true)
                            .autocapitalization(.allCharacters)
                            .keyboardType(.asciiCapable)
                    }
                }

                Section(header: Text("Other")) {
                    Toggle("Upload glucose to Nightscout", isOn: $viewModel.uploadGlucose)
                }
            }
            .navigationTitle("CGM")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
