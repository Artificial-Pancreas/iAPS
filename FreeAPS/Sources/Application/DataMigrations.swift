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

        await runDataNormalizations()
    }

    private func upgradeData(from: Int) async throws {
        switch from {
        case 0: // 0 to 1
            try await migratePreferencesResistanceKey()
        default:
            throw DataMigrationStepError.missingMigration
        }
    }

    /// Data normalizations run on every app start, after the versioned migrations (downgrade-safe).
    private func runDataNormalizations() async {
        do {
            try await Self.normalizeGlucoseSmoothingSettings(storage: BaseFileStorage())
        } catch {
            debug(.service, "glucose smoothing settings not normalized: \(error.localizedDescription)")
        }
        await Self.migrateDemographicsSharing(storage: BaseFileStorage())
    }

    // -------------

    /// upgrade from version 0 -> 1
    /// pre-5.7.1 iAPS had a wrong serialization key for preferences.resistanceLowersTarget (we used to have a work-around in the 'prepare' javascript code, before sending it to oref0)
    /// since version 5.7.1 the key in the json file must be correct
    private func migratePreferencesResistanceKey() async throws {
        try await Self.renameField(
            from: "resistanceLowersTarget",
            to: "resistance_lowers_target",
            inFile: OpenAPS.Settings.preferences,
            storage: BaseFileStorage()
        )
    }

    /// the `smoothGlucose` on/off flag became `glucoseSmoothing`
    nonisolated static func normalizeGlucoseSmoothingSettings(storage: FileStorage) async throws {
        try await updateJSONObject(inFile: OpenAPS.FreeAPS.settings, storage: storage) { dict in
            guard dict["glucoseSmoothing"] == nil else {
                return false
            }
            guard dict["smoothGlucose"] == .bool(true) else {
                return false
            }

            dict["glucoseSmoothing"] = .object([
                "algorithm": .string(GlucoseSmoothingAlgorithm.savitzkyGolay.rawValue),
                "savitzkyGolay": .object(["passes": .number(Decimal(SavitzkyGolayPasses.three.rawValue))])
            ])
            return true
        }
    }

    /// Settings › Sharing's Sex and Age toggles, once, in a settings file without the `demographicsSharingMigrated` key
    /// (an older build's, or one an older build wrote back after a downgrade): each value set stays shared and a legacy
    /// birth date becomes its day (`FreeAPSSettings.migratingDemographicsSharing`, the phone's zone `timeZone`), and
    /// the key is set. The key's presence decides, not its value (it decodes as false without it): a file this build
    /// wrote has it. Only those keys are written (`shareSex`, `shareAge`, `birthDate` when its day differs,
    /// `demographicsSharingMigrated`); every other one, a key this build doesn't know included, stays as it was
    /// (`updateJSONObject`). `sexSetting` and `birthDate` are read as the settings decoder reads them (`JSONCoding`;
    /// missing or unreadable: not set), the day written as any settings save writes a date. Before the settings
    /// manager starts. No file (a fresh install), or one that is not a JSON object: nothing done. A JSON object
    /// `LosslessJSON` can't read (a number out of `Decimal`'s range): left as it is, logged.
    nonisolated static func migrateDemographicsSharing(storage: FileStorage, timeZone: TimeZone = .current) async {
        let file = OpenAPS.FreeAPS.settings
        let migratedKey = "demographicsSharingMigrated"
        var summary: String?
        do {
            try await updateJSONObject(inFile: file, storage: storage) { object in
                guard object[migratedKey] == nil else { return false }
                var settings = FreeAPSSettings()
                if let sexSetting = object["sexSetting"]?.decoded(as: Int.self) {
                    settings.sexSetting = sexSetting
                }
                if let birthDate = object["birthDate"]?.decoded(as: Date.self) {
                    settings.birthDate = birthDate
                }
                let migrated = settings.migratingDemographicsSharing(timeZone: timeZone)
                object["shareSex"] = .bool(migrated.shareSex)
                object["shareAge"] = .bool(migrated.shareAge)
                let birthDateChanged = migrated.birthDate != settings.birthDate
                if birthDateChanged {
                    object["birthDate"] = try LosslessJSON(encoding: migrated.birthDate)
                }
                object[migratedKey] = .bool(true)
                summary =
                    "sex shared \(migrated.shareSex), age shared \(migrated.shareAge), birth date changed \(birthDateChanged)"
                return true
            }
        } catch {
            debug(.service, "file \(file): demographics sharing not migrated: \(error.localizedDescription)")
            return
        }
        guard let summary else { return }
        // the save doesn't throw: read the key back (not there: it runs again at the next start)
        guard let written = await storage.retrieveRaw(file),
              case let .object(writtenObject)? = try? JSONCoding.decoder.decode(LosslessJSON.self, from: Data(written.utf8)),
              writtenObject[migratedKey] == .bool(true)
        else {
            debug(.service, "file \(file) was not written, demographics sharing not migrated")
            return
        }
        debug(.service, "demographics sharing migrated: \(summary)")
    }

    // -------------

    /// Renames a top-level JSON key in `file`, preserving its value.
    nonisolated static func renameField(
        from oldKey: String,
        to newKey: String,
        inFile file: String,
        storage: FileStorage
    ) async throws {
        try await updateJSONObject(inFile: file, storage: storage) { dict in
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
    /// to say there was nothing to do. No file, or one that is not a JSON object (not JSON, or another JSON value), is
    /// not an error - there is nothing to migrate. A JSON object `LosslessJSON` can't read (a number out of `Decimal`'s
    /// range, which JSONSerialization read) throws, the file left as it is: a versioned step fails instead of being
    /// recorded as done without its change.
    /// Read and written as `LosslessJSON`, with `JSONCoding` (the app's file format): every value `transform` leaves
    /// is written back with its value exactly, and its text but for what `LosslessJSON` says; the keys' order and the
    /// spacing may change (as they did through JSONSerialization; the files are read by key). Runs in the caller's
    /// isolation (`transform` isn't sent).
    static func updateJSONObject(
        inFile file: String,
        storage: FileStorage,
        isolation _: isolated(any Actor)? = #isolation,
        transform: (inout [String: LosslessJSON]) throws -> Bool
    ) async throws {
        guard let raw = await storage.retrieveRaw(file) else {
            debug(.service, "file \(file) does not exist, nothing to migrate")
            return
        }
        let data = Data(raw.utf8)
        let decoded: LosslessJSON
        do {
            decoded = try JSONCoding.decoder.decode(LosslessJSON.self, from: data)
        } catch {
            guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                debug(.service, "file \(file) is not json, nothing to migrate")
                return
            }
            throw DataMigrationStepError.undecodableFile(file: file, message: error.localizedDescription)
        }
        guard case var .object(dict) = decoded else {
            debug(.service, "file \(file) is not a json object, nothing to migrate")
            return
        }

        guard try transform(&dict) else { return }

        let out = try JSONCoding.encoder.encode(LosslessJSON.object(dict))
        guard let str = String(data: out, encoding: .utf8)
        else {
            throw DataMigrationStepError.serializationFailed(message: "could not serialize \(file) json")
        }

        await storage.save(str, as: file)
    }
}

/// A JSON value read and written back with its value exactly: a number as a `Decimal` (0.1 stays 0.1, a Double's 17
/// digits stay those 17, 70 stays 70; JSONSerialization would read a Double and write 0.10000000000000001), a boolean as
/// a boolean (tried before a number), `null` kept, a string as its characters, objects and arrays as their values.
/// `DataMigrations.updateJSONObject` edits a file through it, so the keys it doesn't change (and those this build
/// doesn't know) are written back as they were. Their text too, but for these (none of them what the app's encoders
/// write): a number's exponent form is written out (`1e-7` as `0.0000001`, `2.5E3` as `2500`), its trailing zeros
/// dropped (`1.0` as `1`, `0.150` as `0.15`), `-0` written `0`; a string's escapes as `JSONCoding` writes them (`\/` as
/// `/`). A number of more than 38 significant digits is rounded to `Decimal`'s (no app encoder writes one). A number
/// out of `Decimal`'s range, as JSONDecoder reads it (an exponent from 1e128 up or under 1e-128), doesn't decode, nor
/// does the value holding it (`updateJSONObject` then leaves the file as it is and throws).
indirect enum LosslessJSON: Codable, Equatable, Sendable {
    case object([String: LosslessJSON])
    case array([LosslessJSON])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Decimal.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([LosslessJSON].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: LosslessJSON].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(object): try container.encode(object)
        case let .array(array): try container.encode(array)
        case let .string(string): try container.encode(string)
        case let .number(number): try container.encode(number)
        case let .bool(bool): try container.encode(bool)
        case .null: try container.encodeNil()
        }
    }

    /// `value` as the app's files hold it (`JSONCoding`: a `Date` as its ISO 8601 text).
    init<Value: Encodable>(encoding value: Value) throws {
        self = try JSONCoding.decoder.decode(LosslessJSON.self, from: JSONCoding.encoder.encode(value))
    }

    /// This value read as the app reads its files (`JSONCoding`); nil when it isn't one.
    func decoded<Value: Decodable>(as _: Value.Type) -> Value? {
        guard let data = try? JSONCoding.encoder.encode(self) else { return nil }
        return try? JSONCoding.decoder.decode(Value.self, from: data)
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
    case undecodableFile(file: String, message: String)
    case migrationAborted

    var errorDescription: String? {
        switch self {
        case .missingMigration:
            return "migration is not implemented, this is a bug in DataMigrations.swift"
        case let .serializationFailed(message):
            return "data serialization failed: \(message)"
        case let .undecodableFile(file, message):
            return "file \(file) could not be read (a number out of range?), left as it is: \(message)"
        case .migrationAborted:
            return "migration aborted"
        }
    }
}
