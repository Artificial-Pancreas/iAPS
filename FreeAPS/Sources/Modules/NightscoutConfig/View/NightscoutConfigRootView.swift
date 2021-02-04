import SwiftUI

extension NightscoutConfig {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
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
                Button("Connect") { viewModel.connect() }.disabled(viewModel.url.isEmpty || viewModel.secret.isEmpty)
                Button("Delete") { viewModel.delete() }.foregroundColor(.red)
            }
            .toolbar { ToolbarItem(placement: .principal) { Text("Nightscout Config") } }
            .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
