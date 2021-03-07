import SwiftUI

extension Main {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            viewModel.view(for: viewModel.scene.screen)
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
