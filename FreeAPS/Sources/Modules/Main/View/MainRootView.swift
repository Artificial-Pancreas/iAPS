import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @EnvironmentObject var appDelegate: AppDelegate

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
                .onReceive(appDelegate.$notificationAction) { action in
                    switch action {
                    case .snoozeAlert:
                        state.showModal(for: .libreConfig)
                    default: break
                    }
                }
        }
    }
}
