import SwiftUI

extension AuthotizedRoot {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            NavigationView {
                viewModel.rootView
            }
        }
    }
}
