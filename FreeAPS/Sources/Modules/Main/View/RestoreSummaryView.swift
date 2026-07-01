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
    let onNext: () -> Void

    private var router: Router { resolver.resolve(Router.self)! }

    var body: some View {
        NavigationView {
            List {
                Section {
                    reviewRow("Pump Settings", .pumpSettingsEditor)
                    reviewRow("Basal Profile", .basalProfileEditor(saveNewConcentration: false))
                    reviewRow("Insulin Sensitivities", .isfEditor)
                    reviewRow("Carb Ratios", .crEditor)
                    reviewRow("Target Glucose", .targetsEditor)
                } header: { Text("Configuration") }

                Section {
                    reviewRow("OpenAPS", .preferencesEditor)
                } header: { Text("OpenAPS") }

                Section {
                    reviewRow("Auto ISF", .autoISF)
                    reviewRow("Dynamic ISF", .dynamicISF)
                    reviewRow("Bolus Calculator", .bolusCalculatorConfig)
                    reviewRow("Fat And Protein Conversion", .fpuConfig)
                    reviewRow("Calendar", .calendar)
                    reviewRow("Contact Image", .contactTrick)
                    reviewRow("UI/UX", .uiConfig)
                } header: { Text("Extra Features") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review your settings")
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

    private func reviewRow(_ title: LocalizedStringKey, _ screen: Screen) -> some View {
        NavigationLink {
            router.view(for: screen)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text("Review")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
