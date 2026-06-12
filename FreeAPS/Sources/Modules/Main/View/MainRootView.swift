import SwiftUI
import Swinject

extension Main {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        @Environment(\.colorScheme) var lightMode
        @AppStorage(IAPSconfig.hasSeenWelcome) private var hasSeenWelcome = false
        @AppStorage(IAPSconfig.showUpgradeNotice) private var showUpgradeNotice = false
        @AppStorage(IAPSconfig.hasSeenSharingSetup) private var hasSeenSharingSetup = false

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
                    get: { !hasSeenWelcome || showUpgradeNotice || !hasSeenSharingSetup },
                    set: { _ in } // dismissal is flag-driven; the cover content flips the flags
                )) {
                    onboardingCover
                }
        }

        /// The onboarding sequence, run as a single flag-driven cover. Steps advance as each
        /// view flips its flag: Welcome (or post-upgrade notice) → Sharing setup → Home.
        @ViewBuilder private var onboardingCover: some View {
            if !hasSeenWelcome {
                WelcomeView(
                    onExistingUser: {
                        // Advance to the Sharing step; the firstRun-gated migration screen
                        // runs on Home once onboarding finishes.
                        showUpgradeNotice = false
                        hasSeenWelcome = true
                    },
                    onNewUser: {
                        // Advance to the Sharing step. The New-User Setup Wizard (CGM/pump/etc.)
                        // will slot in after sharing once built; for now sharing is step 2.
                        showUpgradeNotice = false
                        hasSeenWelcome = true
                    }
                )
                .environment(\.colorScheme, colorScheme)
            } else if showUpgradeNotice {
                UpgradeNoticeView(
                    version: Bundle.main.releaseVersionNumber ?? "",
                    onReviewSettings: {
                        // The user is heading into Settings; don't stack the Sharing step on
                        // top of the Settings modal — they can reach Sharing from the menu.
                        showUpgradeNotice = false
                        hasSeenSharingSetup = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            state.showModal(for: .settings)
                        }
                    },
                    onDismiss: { showUpgradeNotice = false } // advances to the Sharing step
                )
                .environment(\.colorScheme, colorScheme)
            } else if !hasSeenSharingSetup {
                SharingSetupView(
                    resolver: resolver,
                    onContinue: { hasSeenSharingSetup = true }
                )
                .environment(\.colorScheme, colorScheme)
            }
        }
    }
}

/// Onboarding step 2 (and the one-time first-upgrade prompt): wraps the Sharing screen so a
/// user can turn on Online Backup before later setup steps, then continue. The Sharing screen
/// itself carries the explainer, demographics and the "write down your recovery token" nudge.
struct SharingSetupView: View {
    let resolver: Resolver
    let onContinue: () -> Void

    var body: some View {
        NavigationView {
            Sharing.RootView(resolver: resolver)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue", action: onContinue)
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .interactiveDismissDisabled()
    }
}
