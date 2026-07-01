import Combine
import CoreData
import SwiftUI

enum PresetRestoreStatus {
    case success // pulled N from the server and confirmed N saved
    case failed // saved fewer than were pulled
    case noData // nothing on the server to restore
}

struct PresetOutcome {
    let pulled: Int
    let saved: Int

    var status: PresetRestoreStatus {
        if pulled == 0 { return .noData }
        return saved >= pulled ? .success : .failed
    }
}

struct PresetRestoreResults {
    let meal: PresetOutcome
    let overrides: PresetOutcome
    let tempTargets: PresetOutcome
}

/// Existing-user restore step: pull the CoreData-backed preset sets (meal / override /
/// temp-target) and report what came back. Runs BEFORE the settings summary, because the
/// Settings editors read these lists (e.g. the Hypo-Treatment picker fetches OverridePresets).
///
/// It is a real, awaited step held by this screen — unlike the old fire-and-forget restore,
/// whose fetches were cancelled when the flow's model deallocated (why presets silently didn't
/// restore while the synchronous concentration did). Always shown for existing users, even when
/// everything is "No Data", so a missing backup is visible rather than mistaken for success.
struct RestoreCoreDataStatusView: View {
    let onNext: () -> Void

    @StateObject private var model: Model

    init(token: String, onNext: @escaping () -> Void) {
        self.onNext = onNext
        _model = StateObject(wrappedValue: Model(token: token))
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    if let results = model.results {
                        row("Meal Presets", results.meal)
                        row("Override Presets", results.overrides)
                        row("Temp Target Presets", results.tempTargets)
                    } else {
                        HStack {
                            ProgressView()
                            Text("Restoring…").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Restored data")
                } footer: {
                    Text("Meal, override and temp-target presets from your backup.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Restoring your data")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: onNext) {
                    Text("Next Step")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(model.results == nil ? Color.gray : Color.accentColor)
                        )
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(model.results == nil)
                .padding()
                .background(.regularMaterial)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .interactiveDismissDisabled()
        .onAppear(perform: model.run)
    }

    /// A status row: name + restored count. Deliberately not tappable — the restored count is the
    /// confirmation. There's no onboarding-safe viewer for these: the real Override screen
    /// (`.overrideProfilesConfig`) is an activation UI (tapping a preset STARTS that override, and
    /// its Close only dismisses a modal — a no-op when pushed), so we don't route into it here.
    /// Presets remain reviewable in Settings after setup.
    private func row(_ title: LocalizedStringKey, _ outcome: PresetOutcome) -> some View {
        HStack {
            Text(title)
            Spacer()
            statusLabel(outcome)
        }
    }

    @ViewBuilder
    private func statusLabel(_ outcome: PresetOutcome) -> some View {
        switch outcome.status {
        case .success:
            Label(
                String(format: NSLocalizedString("%d restored", comment: ""), outcome.saved),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            .font(.subheadline)
        case .failed:
            Label(
                String(format: NSLocalizedString("Saved %d of %d", comment: ""), outcome.saved, outcome.pulled),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .font(.subheadline)
        case .noData:
            Text("No Data")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}

extension RestoreCoreDataStatusView {
    final class Model: ObservableObject {
        /// nil while the restore is in flight.
        @Published var results: PresetRestoreResults?

        private let token: String
        private let storage = BaseFileStorage()
        private var lifetime = Set<AnyCancellable>()
        private var started = false

        init(token: String) {
            self.token = token
        }

        func run() {
            guard !started else { return }
            started = true

            let database = Database(token: token)

            let meal = database.fetchMealPressets("default")
                .map { [weak self] payload -> PresetOutcome in
                    PresetOutcome(pulled: payload.presets.count, saved: self?.saveMealPresets(payload.presets) ?? 0)
                }
                .replaceError(with: PresetOutcome(pulled: 0, saved: 0))

            let overrides = database.fetchOverridePressets("default")
                .map { [weak self] payload -> PresetOutcome in
                    PresetOutcome(pulled: payload.presets.count, saved: self?.saveOverridePresets(payload.presets) ?? 0)
                }
                .replaceError(with: PresetOutcome(pulled: 0, saved: 0))

            let tempTargets = database.fetchTempTargets("default")
                .map { [weak self] payload -> PresetOutcome in
                    PresetOutcome(pulled: payload.tempTargets.count, saved: self?.saveTempTargetPresets(payload.tempTargets) ?? 0)
                }
                .replaceError(with: PresetOutcome(pulled: 0, saved: 0))

            Publishers.Zip3(meal, overrides, tempTargets)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] meal, overrides, tempTargets in
                    self?.results = PresetRestoreResults(meal: meal, overrides: overrides, tempTargets: tempTargets)
                }
                .store(in: &lifetime)
        }

        // MARK: - Saves (return the confirmed saved count)

        private func saveMealPresets(_ presets: [MigratedMeals]) -> Int {
            guard !presets.isEmpty else { return 0 }
            let context = CoreDataStack.shared.persistentContainer.viewContext
            var saved = 0
            context.performAndWait {
                for meal in presets {
                    let row = Presets(context: context)
                    row.dish = meal.dish
                    row.carbs = meal.carbs as NSDecimalNumber
                    row.fat = meal.fat as NSDecimalNumber
                    row.protein = meal.protein as NSDecimalNumber
                }
                do {
                    try context.save()
                    saved = presets.count
                } catch {
                    context.rollback()
                    debug(.apsManager, "Restore: meal presets save failed: \(error)")
                }
            }
            return saved
        }

        private func saveOverridePresets(_ presets: [MigratedOverridePresets]) -> Int {
            guard !presets.isEmpty else { return 0 }
            let context = CoreDataStack.shared.persistentContainer.viewContext
            var saved = 0
            context.performAndWait {
                for p in presets {
                    let o = OverridePresets(context: context)
                    o.advancedSettings = p.advancedSettings
                    o.cr = p.cr
                    o.date = p.date
                    o.duration = p.duration as NSDecimalNumber
                    o.emoji = p.emoji
                    o.end = p.end as NSDecimalNumber
                    o.id = p.id
                    o.indefinite = p.indefininite
                    o.isf = p.isf
                    o.isfAndCr = p.isndAndCr
                    o.basal = p.basal
                    o.maxIOB = p.maxIOB as NSDecimalNumber
                    o.name = p.name
                    o.overrideMaxIOB = p.overrideMaxIOB
                    o.percentage = p.percentage
                    o.smbIsAlwaysOff = p.smbAlwaysOff
                    o.smbIsOff = p.smbIsOff
                    o.smbMinutes = p.smbMinutes as NSDecimalNumber
                    o.start = p.start as NSDecimalNumber
                    o.target = p.target as NSDecimalNumber
                    o.uamMinutes = p.uamMinutes as NSDecimalNumber
                }
                do {
                    try context.save()
                    saved = presets.count
                } catch {
                    context.rollback()
                    debug(.apsManager, "Restore: override presets save failed: \(error)")
                }
            }
            return saved
        }

        private func saveTempTargetPresets(_ targets: [TempTarget]) -> Int {
            guard !targets.isEmpty else { return 0 }
            storage.save(targets, as: OpenAPS.FreeAPS.tempTargetsPresets)
            // Confirm by reading the file back.
            return storage.retrieveFile(OpenAPS.FreeAPS.tempTargetsPresets, as: [TempTarget].self)?.count ?? 0
        }
    }
}
