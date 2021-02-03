import SwiftUI

extension ConfigEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            TextEditor(text: $viewModel.configText)
                .font(.system(.subheadline, design: .monospaced))
                .allowsTightening(true)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .toolbar { ToolbarItem(placement: .principal) { Text("preferences.json") } }
                .navigationBarItems(
                    leading: Button("Close", action: viewModel.hideModal),
                    trailing: Button("Save", action: viewModel.save)
                )
                .navigationBarTitleDisplayMode(.inline)
                .padding()
        }
    }
}
