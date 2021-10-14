import SwiftUI

extension Main {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        @ViewBuilder func presentedView() -> some View {
            viewModel.cachedView(for: viewModel.scene.screen)
        }

        var body: some View {
            presentedView()
                .sheet(isPresented: $viewModel.isModalPresented) {
                    NavigationView { self.viewModel.modal!.view }
                        .navigationViewStyle(StackNavigationViewStyle())
                }
                .alert(isPresented: $viewModel.isAlertPresented) {
                    Alert(
                        title: Text("Important message"),
                        message: Text(viewModel.alertMessage),
                        dismissButton: .default(Text("Dismiss"))
                    )
                }
        }
    }
}
