import SwiftUI
import Swinject

/// Device Setup step — pair the pump and CGM before the software-setup summary, so basal rates,
/// dose increment and glucose readings line up with the real hardware. Pump/CGM pairing is
/// per-device and is never restored from a backup, so this is shown to every user (new and
/// existing) alike.
///
/// Reuses iAPS's real Pump and CGM config screens via the Router (`.pumpConfig` / `.cgm`); the
/// LoopKit pairing UI they present runs as its own sheet, and they're pushed (not presented) so
/// their nav back button dismisses them. Row state reflects REAL pairing (DeviceDataManager), not
/// merely whether the screen was opened. Not gated — a user can pair later in Settings.
struct DeviceSetupView: View {
    let resolver: Resolver
    let onNext: () -> Void

    @State private var pumpConfigured = false
    @State private var cgmConfigured = false

    private var router: Router { resolver.resolve(Router.self)! }
    private var deviceManager: DeviceDataManager? { resolver.resolve(DeviceDataManager.self) }

    var body: some View {
        NavigationView {
            List {
                Section {
                    deviceRow("Pump", .pumpConfig, configured: pumpConfigured)
                    deviceRow("CGM", .cgm, configured: cgmConfigured)
                } header: {
                    Text("Devices")
                } footer: {
                    Text(
                        "Pair your pump and CGM so iAPS can read glucose and deliver insulin. You can also set these up later in Settings."
                    )
                }
            }
            .listStyle(.insetGrouped)
            // On the List (the stack's root), not the NavigationView: the container stays in the
            // hierarchy while a config screen is pushed, so its onAppear fires once and never
            // again. The root is what gets covered and uncovered, so this re-runs on every pop
            // back from a config screen and a freshly paired pump/CGM flips its row to done.
            .onAppear(perform: refresh)
            .navigationTitle("Set up your devices")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: onNext) {
                    Text("Next Step")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .padding()
                .background(.regularMaterial)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .interactiveDismissDisabled()
    }

    /// Paired means onboarded: the manager is assigned as soon as pairing STARTS (didCreate…), so
    /// backing out of a half-finished pairing leaves it non-nil. Only a completed onboarding
    /// should earn the check mark.
    private func refresh() {
        pumpConfigured = deviceManager?.pumpManager?.isOnboarded == true
        cgmConfigured = deviceManager?.cgmManager?.isOnboarded == true
    }

    /// "Setup" (accent, a to-do) until the device is paired, then "Review" + green check.
    private func deviceRow(_ title: LocalizedStringKey, _ screen: Screen, configured: Bool) -> some View {
        // Annotated: a bare `cond ? "a" : "b"` is a String, so it would hit Text's verbatim
        // initialiser and ship untranslated.
        let action: LocalizedStringKey = configured ? "Review" : "Setup"

        return NavigationLink {
            router.view(for: screen)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if configured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
                Text(action)
                    .font(.subheadline)
                    .foregroundStyle(configured ? Color.secondary : Color.accentColor)
            }
        }
    }
}
