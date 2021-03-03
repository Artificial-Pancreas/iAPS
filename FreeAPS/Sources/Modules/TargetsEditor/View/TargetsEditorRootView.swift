import SwiftUI

extension TargetsEditor {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Text("TargetsEditor screen")
                .navigationTitle("TargetsEditor")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: Button("Close", action: viewModel.hideModal))
        }
    }
}
