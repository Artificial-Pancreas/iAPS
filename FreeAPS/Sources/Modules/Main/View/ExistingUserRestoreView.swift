import Combine
import CoreData
import SwiftUI
import Swinject

/// Existing-User onboarding step: restore a cloud backup (open-iaps.app) onto a fresh
/// install using the recovery token from the previous install.
/// - Phase A (silent, all-or-nothing): OpenAPS Preferences + the iAPS app settings, plus the
///   pump settings (DIA, max bolus/basal and the insulin concentration — a U200 user left at
///   the U100 default would be mis-dosed) and the Contact Trick display config.
/// - Phase B (reviewed): the profile schedules — basal, ISF, carb ratios and glucose targets —
///   are fetched, decomposed and shown for confirmation before being written; basal syncs to
///   the pump later, at pump setup. A backup with no profile skips straight to done.
/// The remaining CoreData-backed presets are out of scope here and handled separately.
struct ExistingUserRestoreView: View {
    let resolver: Resolver
    /// Advance the onboarding cover to the next step (Sharing setup).
    let onDone: () -> Void
    /// Return to the Welcome New-/Existing-User choice.
    let onBack: () -> Void

    @StateObject private var model: Model
    @FocusState private var tokenFieldFocused: Bool

    init(resolver: Resolver, onDone: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.resolver = resolver
        self.onDone = onDone
        self.onBack = onBack
        _model = StateObject(wrappedValue: Model(resolver: resolver))
    }

    var body: some View {
        Group {
            switch model.state {
            case .reviewing, .applying:
                // Phase B: the profile-schedule review is its own full-screen layout.
                if let review = model.review {
                    ExistingUserProfileReviewView(
                        review: review,
                        isApplying: model.state == .applying,
                        onApply: model.applySchedules,
                        onContinueWithout: model.finish
                    )
                } else {
                    Color.clear.onAppear(perform: model.finish)
                }
            default:
                VStack(spacing: 0) {
                    Spacer()
                    centeredContent
                    Spacer()
                }
                .padding()
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var centeredContent: some View {
        switch model.state {
        case .entry,
             .working:
            entry
        case .done:
            done
        case let .failed(message):
            failure(message)
        default:
            EmptyView()
        }
    }

    // MARK: - Token entry

    private var entry: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("Restore your settings")
                    .font(.largeTitle).bold()
                    .multilineTextAlignment(.center)
                Text("Enter the recovery token from your previous iAPS install to restore your OpenAPS preferences and app settings from your online backup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Recovery token", text: $model.token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($tokenFieldFocused)
                    .disabled(model.state == .working)
                Text("Find this on your old phone under iAPS → Settings → Sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Button(action: model.restore) {
                HStack {
                    if model.state == .working {
                        ProgressView().tint(.white)
                        Text("Restoring…").font(.headline)
                    } else {
                        Text("Restore my settings").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(model.state == .working || model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal)

            Button("Back", action: onBack)
                .disabled(model.state == .working)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Success

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Settings restored")
                .font(.title).bold()
            Text("Your OpenAPS preferences and app settings were restored from your backup. You'll set up online backup for this device on the next step.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onDone) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    // MARK: - Failure

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Restore didn't complete")
                .font(.title2).bold()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try again") { model.reset() }
                .font(.headline)
                .padding(.horizontal)

            Button("Skip and set up fresh", action: onDone)
                .foregroundStyle(.secondary)
        }
    }
}

extension ExistingUserRestoreView {
    final class Model: ObservableObject {
        @Published var token: String = ""
        @Published var state: Phase = .entry
        /// The decomposed schedules awaiting the user's review (Phase B), formatted for display.
        @Published var review: ProfileScheduleReview?

        enum Phase: Equatable {
            case entry
            case working
            case reviewing
            case applying
            case done
            case failed(String)
        }

        private let resolver: Resolver
        private let storage = BaseFileStorage()
        private var lifetime = Set<AnyCancellable>()
        /// Held between review and apply so the confirmed schedules are written verbatim.
        private var decomposed: ProfileScheduleDecomposition.Result?

        init(resolver: Resolver) {
            self.resolver = resolver
        }

        func reset() {
            state = .entry
        }

        func restore() {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else {
                state = .failed(NSLocalizedString("Enter your recovery token.", comment: ""))
                return
            }

            state = .working
            let database = Database(token: token)

            // Preferences + settings gate the restore (all-or-nothing — a fresh install must
            // never end up half-restored). The pump config (DIA / max bolus / max basal + the
            // insulin concentration) is best-effort: it rides an optional pump-settings row that
            // older installs may never have uploaded, so its failure resolves to an empty config
            // rather than failing the whole restore.
            let pumpConfig = database.fetchPumpConfig("default")
                .replaceError(with: PumpRestoreConfig(settings: nil, concentration: nil))
                .setFailureType(to: Swift.Error.self)
                .eraseToAnyPublisher()

            Publishers.Zip3(
                database.fetchPreferences("default"),
                database.fetchSettings("default"),
                pumpConfig
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.state = .failed(NSLocalizedString(
                            "We couldn't find a backup for that token, or the server was unreachable. Check the token and your connection, then try again.",
                            comment: ""
                        ))
                    }
                },
                receiveValue: { [weak self] preferences, settings, pumpConfig in
                    guard let self else { return }

                    // Preferences: oref re-reads preferences.json from disk each run, so a
                    // file write applies on the next loop.
                    self.storage.save(preferences, as: OpenAPS.Settings.preferences)

                    // App settings: route through SettingsManager so the change applies live
                    // (its didSet persists + publishes) rather than being shadowed by the
                    // already-loaded in-memory settings. Fall back to a raw file write.
                    if let manager = self.resolver.resolve(SettingsManager.self) {
                        manager.settings = settings
                    } else {
                        self.storage.save(settings, as: OpenAPS.FreeAPS.settings)
                    }

                    // Pump settings (DIA / max bolus / max basal) → settings.json. The insulin
                    // concentration lives in CoreData, not in any settings file, so it's written
                    // there separately. Both best-effort: a missing value leaves the default.
                    if let pumpSettings = pumpConfig.settings {
                        self.storage.save(pumpSettings, as: OpenAPS.Settings.settings)
                    }
                    if let concentration = pumpConfig.concentration, concentration > 0 {
                        self.saveConcentration(concentration, increment: preferences.bolusIncrement)
                    }

                    // Contact Trick (display config) — best-effort, silent (not dosing).
                    self.restoreContactTrick(using: database)

                    // Phase C presets (meal / temp-target / override) — best-effort, silent.
                    self.restorePresets(using: database)

                    // Phase A is applied. Phase B: best-effort fetch + decompose of the profile
                    // schedules for the review step (a missing profile just finishes).
                    self.loadProfileReview(using: database, units: settings.units)
                }
            )
            .store(in: &lifetime)
        }

        /// Persist the restored insulin concentration as a new `InsulinConcentration` row,
        /// mirroring how the Basal Profile editor records it (most-recent row wins). The
        /// increment comes from the just-restored preferences' bolus increment.
        private func saveConcentration(_ concentration: Double, increment: Decimal) {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            context.perform {
                let row = InsulinConcentration(context: context)
                row.concentration = concentration
                row.incrementSetting = Double(increment)
                row.date = Date.now
                do {
                    try context.save()
                } catch {
                    debug(.apsManager, "Restore: insulin concentration couldn't be saved to CoreData. Error: \(error)")
                }
            }
        }

        /// Best-effort, silent restore of the Contact Trick display config (not dosing): fetch
        /// the backup's contacts and write them to the contact-trick file. A missing backup or
        /// an empty list is a no-op.
        private func restoreContactTrick(using database: Database) {
            database.fetchContactTrick("default")
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] payload in
                        guard let self, !payload.contacts.isEmpty else { return }
                        self.storage.save(payload.contacts, as: OpenAPS.Settings.contactTrick)
                    }
                )
                .store(in: &lifetime)
        }

        /// Best-effort, silent restore of the saved presets (display/convenience data, not
        /// dosing): temp-target presets to their file, and meal + override presets into CoreData.
        /// A fresh install has nothing to collide with, so each set is simply recreated.
        private func restorePresets(using database: Database) {
            // Temp-target presets — a plain file, like the schedules.
            database.fetchTempTargets("default")
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] payload in
                    guard let self, !payload.tempTargets.isEmpty else { return }
                    self.storage.save(payload.tempTargets, as: OpenAPS.FreeAPS.tempTargetsPresets)
                })
                .store(in: &lifetime)

            // Meal presets — CoreData.
            database.fetchMealPressets("default")
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] payload in
                    self?.saveMealPresets(payload.presets)
                })
                .store(in: &lifetime)

            // Override presets — CoreData.
            database.fetchOverridePressets("default")
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] payload in
                    self?.saveOverridePresets(payload.presets)
                })
                .store(in: &lifetime)
        }

        /// Recreate meal presets from the backup (carbs / dish / fat / protein — the fields the
        /// backup captures), mirroring `Presets(context:)` creation in the carb-entry screen.
        private func saveMealPresets(_ presets: [MigratedMeals]) {
            guard !presets.isEmpty else { return }
            let context = CoreDataStack.shared.persistentContainer.viewContext
            context.perform {
                for meal in presets {
                    let row = Presets(context: context)
                    row.dish = meal.dish
                    row.carbs = meal.carbs as NSDecimalNumber
                    row.fat = meal.fat as NSDecimalNumber
                    row.protein = meal.protein as NSDecimalNumber
                }
                try? context.save()
            }
        }

        /// Recreate override presets from the backup — the reverse of
        /// `Database.migrateOverridePresets` (note the backup's spelling of a few keys).
        private func saveOverridePresets(_ presets: [MigratedOverridePresets]) {
            guard !presets.isEmpty else { return }
            let context = CoreDataStack.shared.persistentContainer.viewContext
            context.perform {
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
                try? context.save()
            }
        }

        /// Best-effort: fetch the backup profile, decompose it into native schedules, and (if it
        /// carries any) present the review. A missing or empty profile just finishes — older
        /// backups may predate profile upload, so this never blocks the restore.
        private func loadProfileReview(using database: Database, units: GlucoseUnits) {
            database.fetchProfile("default")
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure = completion { self?.finish() }
                    },
                    receiveValue: { [weak self] profileStore in
                        guard let self else { return }
                        guard let profile = profileStore.store["default"] else { self.finish(); return }
                        let decomposed = ProfileScheduleDecomposition.decompose(profile, units: units)
                        let review = Self.buildReview(decomposed, units: units)
                        guard !review.sections.isEmpty else { self.finish(); return }
                        self.decomposed = decomposed
                        self.review = review
                        self.state = .reviewing
                    }
                )
                .store(in: &lifetime)
        }

        /// Write the reviewed schedules to their native files and regenerate the composed profile
        /// so the restored values take effect. Basal isn't pushed to a pump here — there's none
        /// yet at restore; it syncs when the pump is set up.
        func applySchedules() {
            guard let decomposed else { finish(); return }
            state = .applying

            storage.save(decomposed.basal, as: OpenAPS.Settings.basalProfile)
            storage.save(decomposed.carbRatios, as: OpenAPS.Settings.carbRatios)
            storage.save(decomposed.sensitivities, as: OpenAPS.Settings.insulinSensitivities)
            storage.save(decomposed.targets, as: OpenAPS.Settings.bgTargets)

            // Regenerate settings/profile.json from the new schedules (the same call the editors
            // and Autotune config use). Best-effort: finish regardless of the result.
            if let apsManager = resolver.resolve(APSManager.self) {
                apsManager.makeProfiles()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.finish() }
                    .store(in: &lifetime)
            } else {
                finish()
            }
        }

        /// Advance to the success screen (whose Continue button calls onDone to leave the flow).
        func finish() {
            review = nil
            state = .done
        }

        /// Build the display model from the decomposed schedules — pure formatting, no I/O.
        private static func buildReview(
            _ d: ProfileScheduleDecomposition.Result,
            units: GlucoseUnits
        ) -> ProfileScheduleReview {
            let bg = units == .mmolL ? "mmol/L" : "mg/dL"

            let basalRows = d.basal.map {
                ProfileScheduleReview.Row(time: $0.start, value: "\(format($0.rate)) U/hr")
            }
            let isfRows = d.sensitivities.sensitivities.map {
                ProfileScheduleReview.Row(time: $0.start, value: "\(format($0.sensitivity)) \(bg)")
            }
            let crRows = d.carbRatios.schedule.map {
                ProfileScheduleReview.Row(time: $0.start, value: "\(format($0.ratio)) g/U")
            }
            let targetRows = d.targets.targets.map {
                ProfileScheduleReview.Row(time: $0.start, value: "\(format($0.low)) \(bg)")
            }

            var sections: [ProfileScheduleReview.ScheduleSection] = []
            if !basalRows.isEmpty {
                sections.append(.init(
                    title: NSLocalizedString("Basal rates", comment: ""),
                    summary: segmentSummary(basalRows.count), rows: basalRows
                ))
            }
            if !isfRows.isEmpty {
                sections.append(.init(
                    title: NSLocalizedString("Insulin sensitivity (ISF)", comment: ""),
                    summary: segmentSummary(isfRows.count), rows: isfRows
                ))
            }
            if !crRows.isEmpty {
                sections.append(.init(
                    title: NSLocalizedString("Carb ratios", comment: ""),
                    summary: segmentSummary(crRows.count), rows: crRows
                ))
            }
            if !targetRows.isEmpty {
                sections.append(.init(
                    title: NSLocalizedString("Glucose targets", comment: ""),
                    summary: segmentSummary(targetRows.count), rows: targetRows
                ))
            }

            return ProfileScheduleReview(sections: sections, problems: d.problems)
        }

        private static func segmentSummary(_ count: Int) -> String {
            count == 1
                ? NSLocalizedString("1 segment", comment: "")
                : String(format: NSLocalizedString("%d segments", comment: ""), count)
        }

        /// Trim a Decimal to a clean display string ("0.55", "5.5", "10").
        private static func format(_ value: Decimal) -> String {
            NSDecimalNumber(decimal: value).stringValue
        }
    }
}
