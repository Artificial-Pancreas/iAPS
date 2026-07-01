import SwiftUI
import Swinject

/// Software-Setup summary — a Settings-like list of the sections a restore brought back, each
/// row opening iAPS's REAL editor (via the Router) for optional review/edit. We deliberately
/// reuse the real editors rather than maintain a parallel set, so new upstream settings show up
/// here automatically.
///
/// Deliberately excluded: Pump/CGM and other device setup, Nightscout/Health/Notifications
/// services, App Icons (an OS-level per-install thing we can't restore), Autotune (runtime),
/// Sharing (its own earlier step) and all debug options.
struct RestoreSummaryView: View {
    let resolver: Resolver
    /// New user (defaults, nothing restored): rows start as "Setup" and flip to "Review" once
    /// opened, so the list doubles as a setup checklist. Existing users (restored data) always
    /// read "Review".
    let isNewUser: Bool
    let onNext: () -> Void

    /// Row ids the user has opened this session (drives the Setup → Review flip for new users).
    @State private var visited: Set<String> = []

    private var router: Router { resolver.resolve(Router.self)! }

    var body: some View {
        NavigationView {
            List {
                Section {
                    reviewRow("pump", "Pump Settings", .pumpSettingsEditor)
                    reviewRow("basal", "Basal Profile", .basalProfileEditor(saveNewConcentration: false))
                    reviewRow("isf", "Insulin Sensitivities", .isfEditor)
                    reviewRow("cr", "Carb Ratios", .crEditor)
                    reviewRow("target", "Target Glucose", .targetsEditor)
                } header: { Text("Configuration") }

                Section {
                    reviewRow("openaps", "OpenAPS", .preferencesEditor)
                } header: { Text("OpenAPS") }

                Section {
                    reviewRow("autoisf", "Auto ISF", .autoISF)
                    reviewRow("dynisf", "Dynamic ISF", .dynamicISF)
                    reviewRow("bolus", "Bolus Calculator", .bolusCalculatorConfig)
                    reviewRow("fpu", "Fat And Protein Conversion", .fpuConfig)
                    reviewRow("calendar", "Calendar", .calendar)
                    reviewRow("contact", "Contact Image", .contactTrick)
                    reviewRow("uiux", "UI/UX", .uiConfig)
                } header: { Text("Extra Features") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(isNewUser ? "Set up your settings" : "Review your settings")
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

    private func reviewRow(_ id: String, _ title: LocalizedStringKey, _ screen: Screen) -> some View {
        // New user: "Setup" (accent, a to-do) until opened, then "Review" + check (done). Existing
        // user: always "Review". Marked done when the editor appears — i.e. the user opened it.
        let done = !isNewUser || visited.contains(id)
        let action: LocalizedStringKey = done ? "Review" : "Setup"

        return NavigationLink {
            router.view(for: screen)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { visited.insert(id) }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if isNewUser, visited.contains(id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
                Text(action)
                    .font(.subheadline)
                    .foregroundStyle(done ? Color.secondary : Color.accentColor)
            }
        }
    }
}
