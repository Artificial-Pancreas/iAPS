import SwiftUI

extension ISFEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Text("ISFEditor screen")
                .navigationTitle("ISFEditor")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
