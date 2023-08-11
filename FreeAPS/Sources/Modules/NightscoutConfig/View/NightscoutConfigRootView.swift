import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var portFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    TextField("URL", text: $state.url)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    SecureField("API secret", text: $state.secret)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .textContentType(.password)
                        .keyboardType(.asciiCapable)
                    if !state.message.isEmpty {
                        Text(state.message)
                    }
                    if state.connecting {
                        HStack {
                            Text("Connecting...")
                            Spacer()
                            ProgressView()
                        }
                    }
                }

                Section {
                    Button("Connect") { state.connect() }
                        .disabled(state.url.isEmpty || state.connecting)
                    Button("Delete") { state.delete() }.foregroundColor(.red).disabled(state.connecting)
                }

                Section {
                    Toggle("Upload", isOn: $state.isUploadEnabled)
                    if state.isUploadEnabled {
                        Toggle("Statistics", isOn: $state.uploadStats)
                        Toggle("Glucose", isOn: $state.uploadGlucose)
                    }
                } header: {
                    Text("Allow Uploads")
                }

                Section(header: Text("Local glucose source")) {
                    Toggle("Use local glucose server", isOn: $state.useLocalSource)
                    HStack {
                        Text("Port")
                        DecimalTextField("", value: $state.localPort, formatter: portFormater)
                    }
                }

                Section {
                    Button("Backfill glucose") { state.backfillGlucose() }
                        .disabled(state.url.isEmpty || state.connecting || state.backfilling)
                }
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Nightscout Config")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
