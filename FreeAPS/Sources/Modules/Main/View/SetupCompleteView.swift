import SwiftUI
import Swinject

/// Final onboarding step: confirm setup is done and let the user set Closed Loop before landing
/// on Home. For an existing user the toggle reflects the restored `closedLoop` from their backup;
/// a new user starts from the default (off). Loop stays off until they finish here, so nothing
/// doses during setup.
struct SetupCompleteView: View {
    let resolver: Resolver
    let onFinish: () -> Void

    @State private var closedLoop = false

    private var settingsManager: SettingsManager? { resolver.resolve(SettingsManager.self) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                Text("Setup complete")
                    .font(.largeTitle).bold()
                Text("Your settings are in place. Turn on Closed Loop whenever you're ready for iAPS to adjust insulin automatically — you can always change this later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Toggle(isOn: $closedLoop) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Closed Loop")
                        .font(.headline)
                    Text("Let iAPS automate insulin dosing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal)

            Spacer()

            Button(action: finish) {
                Text("Finish setup")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .padding()
        .interactiveDismissDisabled()
        .onAppear { closedLoop = settingsManager?.settings.closedLoop ?? false }
    }

    private func finish() {
        if let manager = settingsManager, manager.settings.closedLoop != closedLoop {
            manager.settings.closedLoop = closedLoop
        }
        onFinish()
    }
}
