import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        @Environment(\.colorScheme) var lightMode
        @Environment(AppUIState.self) private var appUIState

        var colorScheme: ColorScheme {
            appUIState.lightMode != LightMode.auto ? (appUIState.lightMode == .light ? .light : .dark) : lightMode
        }

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            router.view(for: .home)
                .sheet(isPresented: $state.isModalPresented) {
                    NavigationView {
                        self.state.modal!.view
                            .environmentObject(state)
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .interactiveDismissDisabled(state.shouldPreventModalDismiss)
                    .environment(\.colorScheme, colorScheme)
                }
                .sheet(isPresented: $state.isSecondaryModalPresented) {
                    state.secondaryModalView ?? EmptyView().asAny()
                }
                .environment(\.colorScheme, colorScheme)
        }
    }
}
