import Foundation

/// Pure transform from a backup/Nightscout `ScheduledNightscoutProfile` into iAPS's four
/// native schedule values (basal, carb ratios, insulin sensitivities, BG targets) plus DIA.
///
/// No I/O and no side effects: the caller decides whether (and when) to persist. This mirrors
/// the mapping inside `NightscoutConfigStateModel.importSettings()` but is isolated so the
/// cloud-restore flow can decode and *preview* a backup before anything is written — the
/// review-before-apply gate. Keep the two in sync if the Nightscout profile shape changes.
enum ProfileScheduleDecomposition {
    struct Result {
        let basal: [BasalProfileEntry]
        let carbRatios: CarbRatios
        let sensitivities: InsulinSensitivities
        let targets: BGTargets
        let dia: Decimal
        /// Validation problems that make a schedule unsafe to apply (a non-positive carb ratio
        /// or sensitivity divides downstream; a zero total basal is meaningless). Empty = clean.
        /// The caller should refuse to apply while this is non-empty and surface the messages.
        let problems: [String]
    }

    /// Decompose `profile` into native schedules, expressing glucose-keyed schedules in `units`
    /// (the device's restored display units — same source as the backup, so they agree).
    static func decompose(_ profile: ScheduledNightscoutProfile, units: GlucoseUnits) -> Result {
        var problems: [String] = []

        let carbSchedule = profile.carbratio.map { entry in
            CarbRatioEntry(start: entry.time, offset: offsetMinutes(entry.time), ratio: entry.value)
        }
        if carbSchedule.contains(where: { $0.ratio <= 0 }) {
            problems.append("Carb ratio schedule contains a non-positive value.")
        }
        let carbRatios = CarbRatios(units: .grams, schedule: carbSchedule)

        let basal = profile.basal.map { entry in
            BasalProfileEntry(start: entry.time, minutes: offsetMinutes(entry.time), rate: entry.value)
        }
        // At restore time there is no pump yet, so we can't know whether 0 U/h segments are
        // legal (Omnipod DASH allows them). Use the pump-agnostic safe rule: only a zero/negative
        // 24h total is unambiguously invalid; individual zero segments are left for the user to
        // see in the review diff and for the pump sync to validate at pump-setup time.
        if basal.map(\.rate).reduce(0, +) <= 0 {
            problems.append("Total basal across the day is zero or negative.")
        }

        let sensSchedule = profile.sens.map { entry in
            InsulinSensitivityEntry(sensitivity: entry.value, offset: offsetMinutes(entry.time), start: entry.time)
        }
        if sensSchedule.contains(where: { $0.sensitivity <= 0 }) {
            problems.append("Insulin sensitivity schedule contains a non-positive value.")
        }
        let sensitivities = InsulinSensitivities(
            units: units,
            userPrefferedUnits: units,
            sensitivities: sensSchedule
        )

        // iAPS stores a single target; the Nightscout profile splits low/high. Mirror the
        // existing import, which keys targets off `target_low`.
        let targetSchedule = profile.target_low.map { entry in
            BGTargetEntry(low: entry.value, high: entry.value, start: entry.time, offset: offsetMinutes(entry.time))
        }
        let targets = BGTargets(units: units, userPrefferedUnits: units, targets: targetSchedule)

        return Result(
            basal: basal,
            carbRatios: carbRatios,
            sensitivities: sensitivities,
            targets: targets,
            dia: profile.dia,
            problems: problems
        )
    }

    /// "HH:mm" → minutes past midnight (the offset unit the native schedule entries store).
    private static func offsetMinutes(_ time: String) -> Int {
        let hours = Int(time.prefix(2)) ?? 0
        let minutes = Int(time.suffix(2)) ?? 0
        return (hours * 60) + minutes
    }
}
