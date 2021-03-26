import SwiftUI

extension NightscoutConfig {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        private var portFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    TextField("URL", text: $viewModel.url)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    SecureField("API secret", text: $viewModel.secret)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .textContentType(.password)
                        .keyboardType(.asciiCapable)
                    if !viewModel.message.isEmpty {
                        Text(viewModel.message)
                    }
                    if viewModel.connecting {
                        HStack {
                            Text("Connecting...")
                            Spacer()
                            ProgressView()
                        }
                    }
                }

                Section {
                    Button("Connect") { viewModel.connect() }
                        .disabled(viewModel.url.isEmpty || viewModel.secret.isEmpty || viewModel.connecting)
                    Button("Delete") { viewModel.delete() }.foregroundColor(.red).disabled(viewModel.connecting)
                }

                Section {
                    Toggle("Allow uploads", isOn: $viewModel.isUploadEnabled)
                }

                Section(header: Text("Local glucose source")) {
                    Toggle("Use local glucose server", isOn: $viewModel.useLocalSource)
                    HStack {
                        Text("Port")
                        DecimalTextField("", value: $viewModel.localPort, formatter: portFormater)
                    }
                }
            }
            .navigationBarTitle("Nightscout Config", displayMode: .automatic)
        }
    }
}
