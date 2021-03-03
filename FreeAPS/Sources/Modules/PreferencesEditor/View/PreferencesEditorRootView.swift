import SwiftUI

extension PreferencesEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Text("PreferencesEditor screen")
                .navigationTitle("PreferencesEditor")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
