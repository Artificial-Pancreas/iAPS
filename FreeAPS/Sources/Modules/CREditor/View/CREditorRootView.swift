import SwiftUI

extension CREditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Text("CREditor screen")
                .navigationTitle("CREditor")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
