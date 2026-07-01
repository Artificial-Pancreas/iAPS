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

        // Fresh-install setup position (not persisted — it lives only while the cover is up).
        // hasSeenWelcome stays false for the whole fresh-install flow, so an interrupted setup
        // restarts cleanly at Welcome rather than resuming mid-flow; the flags flip together at
        // the end (SetupComplete).
        @State private var step: SetupStep = .welcome
        /// Recovery token from a successful existing-user restore, threaded to the CoreData preset
        /// step. Empty = new user (or a skipped restore) → no CoreData restore.
        @State private var restoreToken = ""

        private enum SetupStep {
            case welcome
            case existingRestore
            case sharing
            case coreData
            case deviceSetup
            case softwareSetup
            case setupComplete
        }

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

        /// The onboarding cover. A fresh install runs the full unified setup flow (`freshInstallFlow`,
        /// driven by `step`); an upgrade gets only the one-time notice then the shared Sharing step.
        @ViewBuilder private var onboardingCover: some View {
            if !hasSeenWelcome {
                // Fresh install: Welcome → [Existing: restore] → Sharing → [Existing: CoreData] →
                // Software Setup summary → Setup Complete. (Upgrades have hasSeenWelcome = true.)
                freshInstallFlow
                    .environment(\.colorScheme, colorScheme)
            } else if showUpgradeNotice {
                UpgradeNoticeView(
                    version: Bundle.main.releaseVersionNumber ?? "",
                    onDismiss: { showUpgradeNotice = false } // advances to the Sharing step
                )
                .environment(\.colorScheme, colorScheme)
            } else if !hasSeenSharingSetup {
                // Post-upgrade (or a resumed install predating the sharing flag): Sharing only.
                SharingSetupView(
                    resolver: resolver,
                    onContinue: { hasSeenSharingSetup = true }
                )
                .environment(\.colorScheme, colorScheme)
            }
        }

        /// The fresh-install setup step machine. New vs Existing differ only in whether the
        /// screens start from restored data (Existing: token entry + CoreData presets) or defaults
        /// — same Sharing / summary / completion screens, same Home destination.
        @ViewBuilder private var freshInstallFlow: some View {
            switch step {
            case .welcome:
                WelcomeView(
                    onExistingUser: { step = .existingRestore },
                    onNewUser: {
                        restoreToken = ""
                        step = .sharing
                    }
                )
            case .existingRestore:
                ExistingUserRestoreView(
                    resolver: resolver,
                    onDone: { token in
                        restoreToken = token
                        step = .sharing
                    },
                    onBack: { step = .welcome }
                )
            case .sharing:
                // Turn Online Backup on under the NEW device id before restoring CoreData.
                SharingSetupView(resolver: resolver, onContinue: {
                    // Existing users (non-empty token) get the CoreData preset restore first; new
                    // users and skipped restores go straight to device setup.
                    step = restoreToken.isEmpty ? .deviceSetup : .coreData
                })
            case .coreData:
                RestoreCoreDataStatusView(
                    token: restoreToken,
                    onNext: { step = .deviceSetup }
                )
            case .deviceSetup:
                // Pair pump + CGM before the software summary — shown to new and existing users
                // alike (pairing is per-device, never restored).
                DeviceSetupView(resolver: resolver, onNext: { step = .softwareSetup })
            case .softwareSetup:
                RestoreSummaryView(
                    resolver: resolver,
                    isNewUser: restoreToken.isEmpty,
                    onNext: { step = .setupComplete }
                )
            case .setupComplete:
                SetupCompleteView(resolver: resolver, onFinish: {
                    // End of onboarding — flip the persisted anchors together to dismiss the cover.
                    showUpgradeNotice = false
                    hasSeenWelcome = true
                    hasSeenSharingSetup = true
                })
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
