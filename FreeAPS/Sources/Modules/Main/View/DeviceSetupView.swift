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
                    Text("Pair your pump and CGM so iAPS can read glucose and deliver insulin. You can also set these up later in Settings.")
                }
            }
            .listStyle(.insetGrouped)
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
        // Fires on first appear and each time we pop back from a config screen, so a freshly
        // paired pump/CGM flips its row to done.
        .onAppear(perform: refresh)
    }

    private func refresh() {
        pumpConfigured = deviceManager?.pumpManager != nil
        cgmConfigured = deviceManager?.cgmManager != nil
    }

    /// "Setup" (accent, a to-do) until the device is paired, then "Review" + green check.
    private func deviceRow(_ title: LocalizedStringKey, _ screen: Screen, configured: Bool) -> some View {
        NavigationLink {
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
                Text(configured ? "Review" : "Setup")
                    .font(.subheadline)
                    .foregroundStyle(configured ? Color.secondary : Color.accentColor)
            }
        }
    }
}
