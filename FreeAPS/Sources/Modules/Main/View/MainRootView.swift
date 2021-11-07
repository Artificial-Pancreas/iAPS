import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            router.view(for: .home)
                .sheet(isPresented: $state.isModalPresented) {
                    NavigationView { self.state.modal!.view }
                        .navigationViewStyle(StackNavigationViewStyle())
                }
                .alert(isPresented: $state.isAlertPresented) {
                    Alert(
                        title: Text("Important message"),
                        message: Text(state.alertMessage),
                        dismissButton: .default(Text("Dismiss")) {
                            state.isAlertPresented = false
                            state.alertMessage = ""
                        }
                    )
                }
                .onAppear(perform: configureView)
        }
    }
}
