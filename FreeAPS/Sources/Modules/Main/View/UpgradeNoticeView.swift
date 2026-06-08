import SwiftUI

/// Shown once after an app-version upgrade (gated by the `showUpgradeNotice` flag in
/// `Main.RootView`, set in `FreeAPSApp.isNewVersion()` only for real upgrades — fresh
/// installs get `WelcomeView` instead). Upgrades have occasionally reset settings
/// (Closed Loop turned off, Max IOB set to 0); this nudges the user to verify before
/// relying on the loop, then dismisses straight to Home.
///
/// NOTE: deliberately uses its own flag, NOT `IAPSconfig.newVersion`, which is a
/// functional flag (forces a post-upgrade run and is auto-cleared by the stats upload).
struct UpgradeNoticeView: View {
    let version: String
    let onReviewSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 10) {
                Text("iAPS updated")
                    .font(.largeTitle).bold()
                Text(String(
                    format: NSLocalizedString("You're now running version %@.", comment: "Upgrade notice subtitle, %@ is the version number"),
                    version
                ))
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Text("Updates can occasionally reset settings. Before relying on the loop, please confirm Closed Loop is on and Max IOB is not 0.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 14) {
                Button(action: onReviewSettings) {
                    Text("Review Settings")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Continue to Home")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
