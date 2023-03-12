import SwiftUI
import Swinject

extension LibreViewConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            List {
                credentialsSection
                actionsSection
                settingsSection
                actionSection
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("LibreView")
            .navigationBarTitleDisplayMode(.automatic)
            .alert("Information", isPresented: Binding(
                get: { state.alertMessage != nil },
                set: { _, _ in state.alertMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.alertMessage ?? "")
            }
        }

        private var actionSection: some View {
            Section("Actions") {
                Button {
                    state.forceUploadGlocose()
                } label: {
                    if state.onUploading {
                        ProgressView()
                    } else {
                        Text("Force upload glocose")
                    }
                }
                .disabled(state.onUploading)
            }
        }

        private var settingsSection: some View {
            Section {
                Picker("LibreView Server", selection: $state.server) {
                    ForEach(0 ..< Server.allCases.count, id: \.self) { index in
                        let server = Server.allCases[index].rawValue
                        Text(server).tag(server)
                    }
                }
                TextField("Custom server", text: $state.customServer)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                Toggle("Allow uploads", isOn: $state.allowUploadGlucose)
                if #available(iOS 16.0, *) {
                    Picker("Frequency of uploads", selection: $state.uploadsFrequency) {
                        ForEach(LibreViewConfig.UploadsFrequency.allCases, id: \.self) { frequencyItem in
                            Text(frequencyItem.description).tag(frequencyItem.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: state.uploadsFrequency) { _ in state.updateUploadTimestampDelta() }
                } else {
                    // Fallback on earlier versions
                }
            } header: {
                Text("Connection settings")
            } footer: {
                Text("It is recommended to use random uploads, they are more natural")
            }
        }

        private var credentialsSection: some View {
            Section {
                TextField("Login", text: $state.login)
                    .disableAutocorrection(true)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                SecureField("Password", text: $state.password)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textContentType(.password)
                    .keyboardType(.asciiCapable)
            } header: {
                Text("Credentials")
            } footer: {
                if state.lastUpload > 0,
                   let lastUploadDate = Date(timeIntervalSince1970: state.lastUpload),
                   let nextuploadDate = Date(timeIntervalSince1970: state.lastUpload + state.nextUploadDelta)
                {
                    Text(
                        "Last upload on \(state.dateFormatter.string(from: lastUploadDate)). Next upload no earlier than \(state.dateFormatter.string(from: nextuploadDate))"
                    )
                }
            }
        }

        private var actionsSection: some View {
            Section {
                if state.token != "" {
                    Button {
                        state.connect()
                    } label: {
                        if state.onLoading {
                            ProgressView()
                        } else {
                            Text("Update a connection")
                        }
                    }
                    .disabled(state.onLoading)
                    Button {
                        state.token = ""
                    } label: {
                        Text("Remove a connection")
                            .foregroundColor(.red)
                    }
                } else {
                    Button {
                        state.connect()
                    } label: {
                        if state.onLoading {
                            ProgressView()
                        } else {
                            Text("Create a connection")
                        }
                    }
                    .disabled(state.onLoading)
                }
            } footer: {
                if state.token == "" {
                    Text("To use LibreView, you need to enter credentials and create a connection")
                }
            }
        }
    }
}
