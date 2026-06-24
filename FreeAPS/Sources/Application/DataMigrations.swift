import Foundation

@MainActor class DataMigrations: AppService {
    private static let dataVersionKey = "iAPS.dataVersion"

    // current data version for this build
    // upgradeData function MUST handle all upgrades from version 0 up to current version, otherwise the app will not start and will show an error to the user
    //
    // 1 - iAPS 5.7.1: resistanceLowersTarget renamed to resistance_lowers_target in preferences json
    private static let currentDataVersion = 1

    // this is called on app start before anything else is initialized
    func start() async throws {
        let storedDataVersion = UserDefaults.standard.integer(forKey: Self.dataVersionKey)
        if storedDataVersion > Self.currentDataVersion {
            throw DataMigrationsError.dataIsNewer(storedVersion: storedDataVersion, currentVersion: Self.currentDataVersion)
        }
        for updateFrom in storedDataVersion ..< Self.currentDataVersion {
            do {
                debug(.service, "starting data migration from version: \(updateFrom) to version \(updateFrom + 1)")
                try await upgradeData(from: updateFrom)
                debug(.service, "upgraded data from version: \(updateFrom) to version \(updateFrom + 1)")
                UserDefaults.standard.set(updateFrom + 1, forKey: Self.dataVersionKey)
            } catch {
                debug(.service, "data migration failed: \(error.localizedDescription)")
                throw DataMigrationsError.migrationStepFailed(from: updateFrom, to: updateFrom + 1, error: error)
            }
        }
    }

    private func upgradeData(from: Int) async throws {
        switch from {
        case 0: // 0 to 1
            try await migratePreferencesResistanceKey()
        default:
            throw DataMigrationStepError.missingMigration
        }
    }

    // -------------

    /// upgrade from version 0 -> 1
    /// pre-5.7.1 iAPS had a wrong serialization key for preferences.resistanceLowersTarget (we used to have a work-around in the 'prepare' javascript code, before sending it to oref0)
    /// since version 5.7.1 the key in the json file must be correct
    private func migratePreferencesResistanceKey() async throws {
        try await renameField(
            from: "resistanceLowersTarget",
            to: "resistance_lowers_target",
            inFile: OpenAPS.Settings.preferences
        )
    }

    // -------------

    /// Renames a top-level JSON key in `file`, preserving its value.
    private func renameField(from oldKey: String, to newKey: String, inFile file: String) async throws {
        let storage = BaseFileStorage()
        guard let raw = await storage.retrieveRaw(file),
              let data = raw.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            debug(.service, "file \(file) does not exist or is not json, nothing to migrate")
            return
        }

        guard dict[newKey] == nil, let value = dict[oldKey] else {
            debug(.service, "file \(file) is already correct: field \(newKey) exists, field \(oldKey) does not exist")
            return
        }

        dict[newKey] = value
        dict.removeValue(forKey: oldKey)
        debug(.service, "renaming field \(oldKey) -> \(newKey) in \(file)")

        let out = try JSONSerialization.data(withJSONObject: dict)
        guard let str = String(data: out, encoding: .utf8)
        else {
            throw DataMigrationStepError.serializationFailed(message: "could not serialize \(file) json")
        }

        await storage.save(str, as: file)
    }
}

private enum DataMigrationsError: LocalizedError {
    case dataIsNewer(storedVersion: Int, currentVersion: Int)
    case migrationStepFailed(from: Int, to: Int, error: Error)

    var errorDescription: String? {
        switch self {
        case let .migrationStepFailed(from, to, error):
            return "Data migration from version \(from) to version \(to) has failed: \(error.localizedDescription)"
        case let .dataIsNewer(stored, current):
            return "Currently stored data version is \(stored), but the version supported in this build of iAPS is newer - \(current). Please update iAPS to a newer version."
        }
    }
}

private enum DataMigrationStepError: LocalizedError {
    case missingMigration
    case serializationFailed(message: String)
    case migrationAborted

    var errorDescription: String? {
        switch self {
        case .missingMigration:
            return "migration is not implemented, this is a bug in DataMigrations.swift"
        case let .serializationFailed(message):
            return "data serialization failed: \(message)"
        case .migrationAborted:
            return "migration aborted"
        }
    }
}
