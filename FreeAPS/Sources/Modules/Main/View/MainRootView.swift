import SwiftUI

extension Main {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            viewModel.view(for: viewModel.scene.screen)
                .sheet(isPresented: $viewModel.isModalPresented) {
                    NavigationView { self.viewModel.modal!.view }
                }
        }
    }
}
