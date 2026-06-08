import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        @Environment(\.colorScheme) var lightMode
        @AppStorage(IAPSconfig.hasSeenWelcome) private var hasSeenWelcome = false
        @AppStorage(IAPSconfig.showUpgradeNotice) private var showUpgradeNotice = false

        var colorScheme: ColorScheme {
            state.lightMode != LightMode.auto ? (state.lightMode == .light ? .light : .dark) : lightMode
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
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenWelcome || showUpgradeNotice },
                    set: { _ in } // dismissal is flag-driven; the cover content flips the flags
                )) {
                    onboardingCover
                }
        }

        /// First-launch welcome (New vs Existing user) and the post-upgrade review-settings
        /// notice. Both are flag-driven — the views flip the flags, which dismisses the cover.
        @ViewBuilder private var onboardingCover: some View {
            if !hasSeenWelcome {
                WelcomeView(
                    onExistingUser: {
                        // Dismiss to Home; the existing firstRun-gated migration screen runs there.
                        showUpgradeNotice = false
                        hasSeenWelcome = true
                    },
                    onNewUser: {
                        // TODO: present the Setup Wizard here; for now dismiss to Home.
                        showUpgradeNotice = false
                        hasSeenWelcome = true
                    }
                )
                .environment(\.colorScheme, colorScheme)
            } else {
                UpgradeNoticeView(
                    version: Bundle.main.releaseVersionNumber ?? "",
                    onReviewSettings: {
                        showUpgradeNotice = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            state.showModal(for: .settings)
                        }
                    },
                    onDismiss: { showUpgradeNotice = false }
                )
                .environment(\.colorScheme, colorScheme)
            }
        }
    }
}
