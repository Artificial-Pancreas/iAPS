import SwiftUI

/// First-launch welcome screen. Forks the user into the New-User setup wizard or the
/// existing settings-migration flow, and surfaces help links up front. Shown once,
/// gated by the `hasSeenWelcome` flag in `Main.RootView` — it does NOT touch the
/// `firstRun` / Onboarding flag, so the existing migration screen still runs on its own.
struct WelcomeView: View {
    /// Dismiss to Home; the existing `firstRun`-gated migration screen takes over there.
    let onExistingUser: () -> Void
    /// Launch the New-User setup wizard.
    let onNewUser: () -> Void

    private let docsURL = URL(string: "https://iapsdocs.org")!
    private let discordURL = URL(string: "https://discord.com/invite/ptkk2Y264Z")!

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Text("Welcome to iAPS")
                    .font(.largeTitle).bold()
            }

            Spacer()

            // Disclaimer, then the New-/Existing-User fork. Existing User leads into the
            // cloud-backup restore flow; New User advances to the Sharing step.
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Text("iAPS is an open-source artificial pancreas system based on the OpenAPS algorithm.")
                    Text("iAPS is not approved by any health authority. You run this system at your own risk.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                VStack(spacing: 16) {
                    choiceCard(
                        title: "New User",
                        subtitle: "Set up iAPS for the first time",
                        systemImage: "sparkles",
                        prominent: true,
                        action: onNewUser
                    )
                    choiceCard(
                        title: "Existing User",
                        subtitle: "Restore my settings from a previous install",
                        systemImage: "arrow.down.circle",
                        prominent: false,
                        action: onExistingUser
                    )
                }
                .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Text("Stuck? Help is here")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    SwiftUI.Link(destination: docsURL) {
                        Label("Documentation", systemImage: "book")
                    }
                    SwiftUI.Link(destination: discordURL) {
                        Label("Discord support", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .font(.subheadline)
            }
            .padding(.bottom, 28)
        }
        .padding()
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func choiceCard(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(prominent ? Color.white.opacity(0.85) : Color.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .opacity(0.6)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(prominent ? Color.accentColor : Color(.secondarySystemBackground))
            )
            .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
