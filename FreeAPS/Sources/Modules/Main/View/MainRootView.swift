import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @Environment(\.colorScheme) var lightMode

        var colorScheme: ColorScheme {
            state.lightMode != LightMode.auto ? (state.lightMode == .light ? .light : .dark) : lightMode
        }

        var body: some View {
            router.view(for: .home)
                .sheet(isPresented: $state.isModalPresented) {
                    NavigationView { self.state.modal!.view }
                        .navigationViewStyle(StackNavigationViewStyle())
                        .environment(\.colorScheme, colorScheme)
                }
                .sheet(isPresented: $state.isSecondaryModalPresented) {
                    state.secondaryModalView ?? EmptyView().asAny()
                }
                .onAppear(perform: configureView)
                .environment(\.colorScheme, colorScheme)
        }
    }
}
