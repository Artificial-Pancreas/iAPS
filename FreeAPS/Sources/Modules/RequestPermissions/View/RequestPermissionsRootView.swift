import SwiftUI

extension RequestPermissions {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Text("RequestPermissions screen")
                .navigationBarTitle("RequestPermissions")
                .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
