import Combine
import CoreData
import SwiftUI
import Swinject

/// The tuple `Presets.replaceMicronutrients(with:context:)` takes. Named so the restore's `map`
/// has an explicit element type rather than leaning on inference for a labelled tuple.
typealias MicronutrientRestoreValue = (name: String, type: String, unit: String, amount: Decimal, per100: Bool)

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

    init(resolver: Resolver, token: String, onNext: @escaping () -> Void) {
        self.onNext = onNext
        _model = StateObject(wrappedValue: Model(resolver: resolver, token: token))
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

    @ViewBuilder private func statusLabel(_ outcome: PresetOutcome) -> some View {
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
    @MainActor final class Model: ObservableObject {
        /// nil while the restore is in flight.
        @Published var results: PresetRestoreResults?

        private let token: String
        private let storage = BaseFileStorage()
        private var lifetime = Set<AnyCancellable>()
        private var started = false

        private let tempTargetsStorage: TempTargetsStorage
        private let overrideStorage: OverrideStorage

        init(resolver: Resolver, token: String) {
            self.token = token
            tempTargetsStorage = resolver.resolve(TempTargetsStorage.self)!
            overrideStorage = resolver.resolve(OverrideStorage.self)!
        }

        func run() {
            guard !started else { return }
            started = true
            Task {
                let database = Database(userToken: StaticUserToken(token))

                let meal: PresetOutcome
                if let payload = try? await database.fetchMealPresets("default") {
                    let saved = await self.saveMealPresets(payload.presets)
                    meal = PresetOutcome(pulled: payload.presets.count, saved: saved)
                } else {
                    meal = PresetOutcome(pulled: 0, saved: 0)
                }

                let overrides: PresetOutcome
                if let payload = try? await database.fetchOverridePressets("default") {
                    let saved = await self.saveOverridePresets(payload.presets)
                    overrides = PresetOutcome(pulled: payload.presets.count, saved: saved)
                } else {
                    overrides = PresetOutcome(pulled: 0, saved: 0)
                }

                let tempTargets: PresetOutcome
                if let payload = try? await database.fetchTempTargets("default") {
                    let saved = await self.saveTempTargetPresets(payload.tempTargets)
                    tempTargets = PresetOutcome(pulled: payload.tempTargets.count, saved: saved)
                } else {
                    tempTargets = PresetOutcome(pulled: 0, saved: 0)
                }

                self.results = PresetRestoreResults(meal: meal, overrides: overrides, tempTargets: tempTargets)
            }
        }

        // MARK: - Saves (return the confirmed saved count)

        private func saveMealPresets(_ presets: [MigratedMeals]) async -> Int {
            guard !presets.isEmpty else { return 0 }
            return await CoreDataStack.shared.persistentContainer.performBackgroundTask { @Sendable context in
                var saved = 0
                for meal in presets {
                    let row = Presets(context: context)
                    row.dish = meal.dish
                    row.carbs = meal.carbs as NSDecimalNumber
                    row.fat = meal.fat as NSDecimalNumber
                    row.protein = meal.protein as NSDecimalNumber
                    // Everything below is Optional in the payload: a backup from a build that
                    // predates the AI food-search fields carries only the macros above, and
                    // leaving the attribute untouched is the right answer for a missing field.
                    if let v = meal.fiber { row.fiber = v as NSDecimalNumber }
                    if let v = meal.sugars { row.sugars = v as NSDecimalNumber }
                    if let v = meal.glycemicIndex { row.glycemicIndex = v as NSDecimalNumber }
                    if let v = meal.portionSize { row.portionSize = v as NSDecimalNumber }
                    if let v = meal.standardServingSize { row.standardServingSize = v as NSDecimalNumber }
                    if let v = meal.per100 { row.per100 = v }
                    if let v = meal.mealUnits { row.mealUnits = v }
                    if let v = meal.standardName { row.standardName = v }
                    if let v = meal.standardServing { row.standardServing = v }
                    if let v = meal.imageURL { row.imageURL = v }
                    if let v = meal.tags { row.tags = v }
                    if let v = meal.foodID { row.foodID = UUID(uuidString: v) }

                    if let micros = meal.micronutrients, !micros.isEmpty {
                        // Looks each definition up by name and creates it when the restoring
                        // device doesn't know it yet. Best-effort: a preset that can't take its
                        // micronutrients still restores with its macros.
                        let values = micros.map { m -> MicronutrientRestoreValue in
                            (
                                name: m.name,
                                type: m.type ?? "",
                                unit: m.unit ?? "",
                                amount: m.amount ?? 0,
                                per100: m.per100 ?? false
                            )
                        }
                        try? row.replaceMicronutrients(with: values, context: context)
                    }
                }
                do {
                    try context.save()
                    saved = presets.count
                } catch {
                    context.rollback()
                    debug(.apsManager, "Restore: meal presets save failed: \(error)")
                }
                return saved
            }
        }

        private func saveOverridePresets(_ presets: [MigratedOverridePresets]) async -> Int {
            guard !presets.isEmpty else { return 0 }

            for p in presets {
                await overrideStorage.storeOverridePreset(
                    .init(
                        id: UUID().uuidString,
                        name: p.name,
                        emoji: p.emoji,
                        percentage: p.percentage,
                        indefinite: p.indefininite,
                        duration: p.duration,
                        target: p.target,
                        basal: p.basal,
                        cr: p.cr,
                        isf: p.isf,
                        isfAndCr: false, // TODO: missing
                        advancedSettings: p.advancedSettings,
                        endWIthNewCarbs: false, // TODO: missing
                        glucoseOverrideThreshold: nil, // TODO: missing
                        glucoseOverrideThresholdActive: false, // TODO: missing
                        glucoseOverrideThresholdActiveDown: false, // TODO: missing
                        glucoseOverrideThresholdDown: nil, // TODO: missing
                        overrideMaxIOB: p.overrideMaxIOB,
                        maxIOB: p.maxIOB,
                        smbIsAlwaysOff: p.smbAlwaysOff,
                        smbIsOff: p.smbIsOff,
                        start: p.start,
                        end: p.end,
                        smbMinutes: p.smbMinutes,
                        uamMinutes: p.uamMinutes,
                        overrideAutoISF: p.overrideMaxIOB,
                        date: p.date,
                        aisf: p.autoISF.map { $0.asSettings(id: p.id) }
                    )
                )
            }
            return presets.count
        }

        /// Writes one restored Auto ISF block. Called inside the override-preset save's
        /// `performAndWait`, so it doesn't save the context itself — the caller's `save()` commits
        /// the presets and their Auto ISF rows together.
        private func saveAutoISF(_ settings: AutoISFsettings, context: NSManagedObjectContext) {
            let row = Auto_ISF(context: context)
            row.id = settings.id
            row.date = Date.now
            row.autoisf = settings.autoisf
            row.autocr = settings.autocr
            row.autoISFhourlyChange = settings.autoISFhourlyChange as NSDecimalNumber
            row.autoisf_min = settings.autoisf_min as NSDecimalNumber
            row.autoisf_max = settings.autoisf_max as NSDecimalNumber
            row.enableBGacceleration = settings.enableBGacceleration
            row.bgAccelISFweight = settings.bgAccelISFweight as NSDecimalNumber
            row.bgBrakeISFweight = settings.bgBrakeISFweight as NSDecimalNumber
            row.lowerISFrangeWeight = settings.lowerISFrangeWeight as NSDecimalNumber
            row.higherISFrangeWeight = settings.higherISFrangeWeight as NSDecimalNumber
            row.postMealISFweight = settings.postMealISFweight as NSDecimalNumber
            row.iTime_Start_Bolus = settings.iTime_Start_Bolus as NSDecimalNumber
            row.iTime_target = settings.iTime_target as NSDecimalNumber
            row.use_B30 = settings.use_B30
            row.b30_duration = settings.b30_duration as NSDecimalNumber
            row.b30factor = settings.b30factor as NSDecimalNumber
            row.b30targetLevel = settings.b30targetLevel as NSDecimalNumber
            row.b30upperLimit = settings.b30upperLimit as NSDecimalNumber
            row.b30upperdelta = settings.b30upperdelta as NSDecimalNumber
            row.iobThresholdPercent = settings.iobThresholdPercent as NSDecimalNumber
            row.ketoProtect = settings.ketoProtect
            row.variableKetoProtect = settings.variableKetoProtect
            row.ketoProtectAbsolut = settings.ketoProtectAbsolut
            row.ketoProtectBasalPercent = settings.ketoProtectBasalPercent as NSDecimalNumber
            row.ketoProtectBasalAbsolut = settings.ketoProtectBasalAbsolut as NSDecimalNumber
            row.smbDeliveryRatioBGrange = settings.smbDeliveryRatioBGrange as NSDecimalNumber
            row.smbDeliveryRatioMin = settings.smbDeliveryRatioMin as NSDecimalNumber
            row.smbDeliveryRatioMax = settings.smbDeliveryRatioMax as NSDecimalNumber
            row.nightTime = NightTimeConfigurationBox(settings.nightTime)
        }

        private func saveTempTargetPresets(_ targets: [TempTarget]) async -> Int {
            guard !targets.isEmpty else { return 0 }
            await tempTargetsStorage.storeTempTargets(targets)
            return await tempTargetsStorage.presets().count
        }
    }
}
