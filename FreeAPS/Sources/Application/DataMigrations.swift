import Foundation
import Observation

/// One change to the stored data, applied once per install (`DataMigrations.builtInRegistry`).
/// `description` and `downgradeInfo` are user-facing and localized: they are stored with the record when the migration
/// is applied, because an older build has no entry for a migration it does not know and can only show what was stored.
struct DataMigration: Sendable {
    /// Stable, never reused, never renamed: the stored records are matched to the registry by it.
    let id: String
    /// What changed, for the user.
    let description: String
    /// What the user should check after going back to a build without this migration (which settings, …).
    let downgradeInfo: String?
    /// `false`: a build without this migration must not use the data at all (it does not start).
    let downgradable: Bool
    /// MUST be safe to run twice: it runs again after a downgrade was acknowledged and the app updated again, and
    /// after a start that failed between the migration and its record.
    let run: @Sendable() async throws -> Void

    init(
        id: String,
        description: String,
        downgradeInfo: String? = nil,
        downgradable: Bool = true,
        run: @escaping @Sendable() async throws -> Void
    ) {
        self.id = id
        self.description = description
        self.downgradeInfo = downgradeInfo
        self.downgradable = downgradable
        self.run = run
    }
}

/// A migration that was applied on this install, as stored in UserDefaults. Older builds read the records newer
/// builds wrote: fields may be added, none of these may be removed, renamed or change its type.
struct DataMigrationRecord: Codable, Equatable, Sendable {
    let id: String
    let description: String
    let downgradeInfo: String?
    let downgradable: Bool
    let appliedAt: Date
    let appVersion: String
}

/// The applied migrations' records in a `UserDefaults` (JSON under one key).
struct DataMigrationRecordStore {
    static let key = "iAPS.dataMigrations.applied"

    let defaults: UserDefaults

    /// No value: no records. A value that can't be read throws (`DataMigrationsError.recordsUnreadable`): the app does
    /// not guess what was applied.
    func load() throws -> [DataMigrationRecord] {
        guard let stored = defaults.object(forKey: Self.key) else { return [] }
        do {
            guard let data = stored as? Data else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not a data value"))
            }
            return try JSONDecoder().decode([DataMigrationRecord].self, from: data)
        } catch {
            throw DataMigrationsError.recordsUnreadable(error: error)
        }
    }

    func save(_ records: [DataMigrationRecord]) throws {
        defaults.set(try JSONEncoder().encode(records), forKey: Self.key)
    }
}

/// What a start does, from the stored records and this build's registry (`DataMigrations.plan`).
enum DataMigrationPlan {
    /// No record of an unknown migration: these registered migrations have no record and run, in registry order.
    case run([DataMigration])
    /// The data was last used by a newer build (records this build has no migration for), all of them downgradable:
    /// the user is warned and must acknowledge before anything runs.
    case downgradeWarning([DataMigrationRecord])
    /// A newer build applied these non-downgradable migrations: the app does not start.
    case blocked([DataMigrationRecord])
}

@MainActor @Observable class DataMigrations: AppService {
    /// The integer data version older builds kept. Not read; removed when the migrations run.
    nonisolated static let legacyDataVersionKey = "iAPS.dataVersion"

    /// This build's migrations, in the order they run. Add new ones at the end.
    /// - The id is stable and never reused, also not after a migration is removed from this list (removing one makes
    ///   its records look like a newer build's: a downgrade warning).
    /// - Every migration MUST be safe to run twice (see `DataMigration.run`).
    /// - Description and downgrade info are localized (`NSLocalizedString`) and written for the user.
    var builtInRegistry: [DataMigration] {
        [
            // iAPS 5.7.1: resistanceLowersTarget renamed to resistance_lowers_target in preferences json
            DataMigration(
                id: "preferences-resistance-key",
                description: NSLocalizedString(
                    "Preferences: the \"resistance lowers target\" setting was stored under a new name",
                    comment: "Data migration description (shown after a downgrade): the preferences key of Resistance Lowers Target was renamed"
                ),
                downgradeInfo: NSLocalizedString(
                    "Check Preferences › Resistance Lowers Target",
                    comment: "Data migration downgrade info: what to check after going back to an older app version"
                ),
                run: { [self] in try await migratePreferencesResistanceKey() }
            )
        ]
    }

    /// The records of a newer build's migrations, while the start waits for the user to acknowledge them
    /// (`acknowledgeDowngrade`). Observed by the startup screen.
    private(set) var downgradeWarning: [DataMigrationRecord]?

    @ObservationIgnored private var acknowledgement: CheckedContinuation<Void, Never>?

    /// UserDefaults is thread-safe (not marked Sendable); set in the nonisolated init
    private nonisolated(unsafe) let defaults: UserDefaults
    private var store: DataMigrationRecordStore { DataMigrationRecordStore(defaults: defaults) }
    private let injectedRegistry: [DataMigration]?
    private let appVersion: String

    /// `registry` nil: this build's (`builtInRegistry`). Nonisolated: the container's factory creates it.
    nonisolated init(
        defaults: UserDefaults = .standard,
        registry: [DataMigration]? = nil,
        appVersion: String = DataMigrations.currentAppVersion
    ) {
        self.defaults = defaults
        injectedRegistry = registry
        self.appVersion = appVersion
    }

    nonisolated static var currentAppVersion: String {
        "\(Bundle.main.releaseVersionNumber ?? "?") (\(Bundle.main.buildVersionNumber ?? "?"))"
    }

    /// Pure: what to do with `records` in a build that has `registry`.
    nonisolated static func plan(records: [DataMigrationRecord], registry: [DataMigration]) -> DataMigrationPlan {
        let known = Set(registry.map(\.id))
        let unknown = records.filter { !known.contains($0.id) }
        let blocking = unknown.filter { !$0.downgradable }
        guard blocking.isEmpty else { return .blocked(blocking) }
        guard unknown.isEmpty else { return .downgradeWarning(unknown) }
        let applied = Set(records.map(\.id))
        return .run(registry.filter { !applied.contains($0.id) })
    }

    // this is called on app start before anything else is initialized
    func start() async throws {
        try await runMigrations()
        await runDataNormalizations()
    }

    /// The registered migrations without a record, in registry order, a record written after each. Throws - and the app
    /// does not start - when a migration fails, when the records can't be read, and when a newer build applied a
    /// non-downgradable migration. With a newer build's downgradable records it waits, nothing run and nothing
    /// removed, until `acknowledgeDowngrade()`; then those records are removed (their migrations run again after the
    /// next update) and the start goes on.
    func runMigrations() async throws {
        let registry = injectedRegistry ?? builtInRegistry
        var records = try store.load()

        var plan = Self.plan(records: records, registry: registry)
        if case let .downgradeWarning(unknown) = plan {
            for record in unknown {
                debug(
                    .service,
                    "data migration record of a newer build: \(record.id) (\(record.description)), applied \(record.appliedAt) by \(record.appVersion), downgradable"
                )
            }
            downgradeWarning = unknown
            await withCheckedContinuation { self.acknowledgement = $0 }
            downgradeWarning = nil

            let unknownIDs = Set(unknown.map(\.id))
            records.removeAll { unknownIDs.contains($0.id) }
            try store.save(records)
            debug(.service, "downgrade acknowledged, data migration records removed: \(unknownIDs.sorted())")
            plan = Self.plan(records: records, registry: registry)
        }

        switch plan {
        case let .blocked(blocking):
            for record in blocking {
                debug(
                    .service,
                    "data migration record of a newer build: \(record.id) (\(record.description)), applied \(record.appliedAt) by \(record.appVersion), NOT downgradable"
                )
            }
            throw DataMigrationsError.dataIsNewer(records: blocking)
        case .downgradeWarning:
            // not reachable: the acknowledged records were removed above
            throw DataMigrationStepError.migrationAborted
        case let .run(pending):
            defaults.removeObject(forKey: Self.legacyDataVersionKey)
            for migration in pending {
                do {
                    debug(.service, "starting data migration \(migration.id)")
                    try await migration.run()
                    records.append(DataMigrationRecord(
                        id: migration.id,
                        description: migration.description,
                        downgradeInfo: migration.downgradeInfo,
                        downgradable: migration.downgradable,
                        appliedAt: Date(),
                        appVersion: appVersion
                    ))
                    try store.save(records)
                    debug(.service, "applied data migration \(migration.id) (\(migration.description))")
                } catch {
                    debug(.service, "data migration \(migration.id) failed: \(error.localizedDescription)")
                    throw DataMigrationsError.migrationFailed(
                        id: migration.id,
                        description: migration.description,
                        error: error
                    )
                }
            }
        }
    }

    /// The user's "I understand, continue to the app" on the downgrade warning. Does nothing when no warning is
    /// waiting (a blocked start can't be acknowledged).
    func acknowledgeDowngrade() {
        guard let acknowledgement else { return }
        self.acknowledgement = nil
        acknowledgement.resume()
    }

    /// Data normalizations run on every app start, after the versioned migrations (downgrade-safe).
    private func runDataNormalizations() async {
        try? await normalizeGlucoseSmoothingSettings()
    }

    // -------------

    /// migration `preferences-resistance-key`
    /// pre-5.7.1 iAPS had a wrong serialization key for preferences.resistanceLowersTarget (we used to have a work-around in the 'prepare' javascript code, before sending it to oref0)
    /// since version 5.7.1 the key in the json file must be correct
    private func migratePreferencesResistanceKey() async throws {
        try await renameField(
            from: "resistanceLowersTarget",
            to: "resistance_lowers_target",
            inFile: OpenAPS.Settings.preferences
        )
    }

    /// the `smoothGlucose` on/off flag became `glucoseSmoothing`
    private func normalizeGlucoseSmoothingSettings() async throws {
        try await updateJSONObject(inFile: OpenAPS.FreeAPS.settings) { dict in
            guard dict["glucoseSmoothing"] == nil else {
                return false
            }
            guard let smoothGlucose = dict["smoothGlucose"] as? Bool, smoothGlucose else {
                return false
            }

            dict["glucoseSmoothing"] = [
                "algorithm": GlucoseSmoothingAlgorithm.savitzkyGolay.rawValue,
                "savitzkyGolay": ["passes": SavitzkyGolayPasses.three.rawValue]
            ] as [String: Any]
            return true
        }
    }

    // -------------

    /// Renames a top-level JSON key in `file`, preserving its value.
    private func renameField(from oldKey: String, to newKey: String, inFile file: String) async throws {
        try await updateJSONObject(inFile: file) { dict in
            guard dict[newKey] == nil, let value = dict[oldKey] else {
                debug(.service, "file \(file) is already correct: field \(newKey) exists, field \(oldKey) does not exist")
                return false
            }

            dict[newKey] = value
            dict.removeValue(forKey: oldKey)
            debug(.service, "renaming field \(oldKey) -> \(newKey) in \(file)")
            return true
        }
    }

    /// Reads `file` as a top-level JSON object and writes it back, unless `transform` returns `false`
    /// to say there was nothing to do. A missing or non-object file is not an error - there is nothing to migrate.
    private func updateJSONObject(inFile file: String, transform: (inout [String: Any]) -> Bool) async throws {
        let storage = BaseFileStorage()
        guard let raw = await storage.retrieveRaw(file),
              let data = raw.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            debug(.service, "file \(file) does not exist or is not json, nothing to migrate")
            return
        }

        guard transform(&dict) else { return }

        let out = try JSONSerialization.data(withJSONObject: dict)
        guard let str = String(data: out, encoding: .utf8)
        else {
            throw DataMigrationStepError.serializationFailed(message: "could not serialize \(file) json")
        }

        await storage.save(str, as: file)
    }
}

enum DataMigrationsError: LocalizedError {
    /// a newer build applied these non-downgradable migrations
    case dataIsNewer(records: [DataMigrationRecord])
    case migrationFailed(id: String, description: String, error: Error)
    case recordsUnreadable(error: Error)

    var errorDescription: String? {
        switch self {
        case let .migrationFailed(id, description, error):
            return String(
                format: NSLocalizedString(
                    "Data migration \"%1$@\" (%2$@) has failed: %3$@",
                    comment: "App cannot start: a data migration failed. 1: the migration's description, 2: its id, 3: the error"
                ),
                description,
                id,
                error.localizedDescription
            )
        case let .dataIsNewer(records):
            return String(
                format: NSLocalizedString(
                    "iAPS cannot start: the data on this phone was changed by a newer version of iAPS in a way this version cannot use.\n\n%@\n\nPlease update iAPS to a newer version.",
                    comment: "App cannot start after a downgrade. %@: the list of changes the newer version made, one per line"
                ),
                records.map { "• \($0.description) (\($0.appVersion))" }.joined(separator: "\n")
            )
        case let .recordsUnreadable(error):
            return String(
                format: NSLocalizedString(
                    "iAPS cannot start: the list of applied data migrations cannot be read (%@). It may have been written by a newer version of iAPS - please update iAPS to a newer version.",
                    comment: "App cannot start: the stored data migration records are unreadable. %@: the error"
                ),
                error.localizedDescription
            )
        }
    }
}

private enum DataMigrationStepError: LocalizedError {
    case serializationFailed(message: String)
    case migrationAborted

    var errorDescription: String? {
        switch self {
        case let .serializationFailed(message):
            return "data serialization failed: \(message)"
        case .migrationAborted:
            return "migration aborted"
        }
    }
}
