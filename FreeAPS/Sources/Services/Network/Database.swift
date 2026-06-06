import Foundation
import Swinject

class Database: Injectable {
    @Injected() private var userToken: Token!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    private enum Config {
        static let uploadStatisticsPath = "/api/v1/upload/statistics"
        static let uploadPreferencesPath = "/api/v1/upload/preferences"
        static let uploadSettingsPath = "/api/v1/upload/settings"
        static let uploadProfilesPath = "/api/v1/upload/profiles"
        static let uploadPumpSettingsPath = "/api/v1/upload/pump-settings"
        static let uploadTempTargetsPath = "/api/v1/upload/temp-targets"
        static let uploadMealPresetsPath = "/api/v1/upload/meal-presets"
        static let uploadOverridePresetsPath = "/api/v1/upload/override-presets"
        static let versionPath = "/api/v1/version_check"
        static let downloadListPath = "/api/v1/download/list"
        static let downloadPreferencesPath = "/api/v1/download/preferences"
        static let downloadSettingsPath = "/api/v1/download/settings"
        static let downloadProfilePath = "/api/v1/download/profile"
        static let downloadPumpSettingsPath = "/api/v1/download/pump-settings"
        static let downloadTempTargetsPath = "/api/v1/download/temp-targets"
        static let downloadMealPresetsPath = "/api/v1/download/meal-presets"
        static let downloadOverridePresetsPath = "/api/v1/download/override-presets"
        static let downloadDeletePath = "/api/v1/download/delete"
        static let downloadRestorePath = "/api/v1/download/restore"
        static let uploadLogsPath = "/api/v1/upload/logs"

        static let retryCount = 2
        static let timeout: TimeInterval = 60
    }

    private let url: URL = IAPSconfig.statURL

    private let service = NetworkService()
}

extension Database {
    func fetchPreferences(_ name: String) async throws -> Preferences {
        try await sendPostRequest(
            Config.downloadPreferencesPath,
            payload: ["token": userToken.getIdentifier(), "profile": name],
            as: Preferences.self
        )
    }

    func moveProfiles(token: String, restoreToken: String) async throws {
        try await sendPostRequest(Config.downloadRestorePath, payload: ["token": token, "restore_token": restoreToken])
    }

    func fetchProfiles() async throws -> ProfileList {
        try await sendPostRequest(
            Config.downloadListPath,
            payload: ["token": userToken.getIdentifier()],
            as: ProfileList.self
        )
    }

    func fetchSettings(_ name: String) async throws -> FreeAPSSettings {
        //        TODO: is this custom decoder needed here?
        //        let decoder = JSONDecoder()
        //        decoder.dateDecodingStrategy = .customISO8601
        try await sendPostRequest(
            Config.downloadSettingsPath,
            payload: ["token": userToken.getIdentifier(), "profile": name],
            as: FreeAPSSettings.self
        )
    }

    func fetchProfile(_ name: String) async throws -> NightscoutProfileStore {
        try await sendPostRequest(
            Config.downloadProfilePath,
            payload: ["token": userToken.getIdentifier(), "profile": name],
            as: NightscoutProfileStore.self
        )
    }

    func deleteProfile(_ name: String) async throws {
        try await sendPostRequest(
            Config.downloadDeletePath,
            payload: ["token": userToken.getIdentifier(), "profile": name]
        )
    }

    func fetchPumpSettings(_ name: String) async throws -> PumpSettings {
        try await sendPostRequest(
            Config.downloadPumpSettingsPath,
            payload: ["token": userToken.getIdentifier(), "profile": name],
            as: PumpSettings.self
        )
    }

    func fetchTempTargets(_ name: String) async throws -> DatabaseTempTargets {
        try await sendPostRequest(
            Config.downloadTempTargetsPath,
            payload: ["token": userToken.getIdentifier(), "profile": name],
            as: DatabaseTempTargets.self,
            allowsConstrainedNetworkAccess: true
        )
    }

    func fetchMealPresets(_ name: String) async throws -> DatabaseMeal {
        try await sendPostRequest(
            Config.downloadMealPresetsPath,
            payload: ["token": userToken.getIdentifier(), "profile": name],
            as: DatabaseMeal.self
        )
    }

    func fetchOverridePressets(_ name: String) async throws -> DatabaseOverride {
        try await sendPostRequest(
            Config.downloadOverridePresetsPath,
            payload: ["token": userToken.getIdentifier(), "profile": name],
            as: DatabaseOverride.self,
            allowsConstrainedNetworkAccess: true
        )
    }

    private struct ProfilesPayload: JSON {
        let defaultProfile: String
        let startDate: Date
        let mills: Int
        let units: String
        let store: [String: ScheduledNightscoutProfile]
        let profile: String?
        var enteredBy: String
    }

    func uploadProfile(_ profile: NightscoutProfileStore) async throws {
        let payload = ProfilesPayload(
            defaultProfile: profile.defaultProfile,
            startDate: profile.startDate,
            mills: profile.mills,
            units: profile.units,
            store: profile.store,
            profile: profile.profile,
            enteredBy: userToken.getIdentifier()
        )
        try await sendPostRequest(
            Config.uploadProfilesPath,
            payload: payload
        )
    }

    private struct StatisticsUploadPayload: JSON {
        var report = "statistics"
        let dailystats: Statistics?
        let justVersion: DatabaseStatisticsVersion?
    }

    func uploadStats(
        stats: Statistics?,
        version: DatabaseStatisticsVersion?
    ) async throws {
        let token = userToken.getIdentifier()
        let dailystats = stats.map { stats in
            var withId = stats
            withId.id = token
            return withId
        }
        let justVersion = version.map { version in
            var withId = version
            withId.id = token
            return withId
        }
        let statsPayload =
            StatisticsUploadPayload(
                dailystats: dailystats,
                justVersion: justVersion
            )

        try await sendPostRequest(
            Config.uploadStatisticsPath,
            payload: statsPayload
        )
    }

    private struct PreferencesPayload: Encodable {
        var report = "preferences"
        let preferences: Preferences?
        let profile: String?
        let enteredBy: String
    }

    func uploadPrefs(_ prefs: DatabasePreferences) async throws {
        let payload = PreferencesPayload(
            preferences: prefs.preferences,
            profile: prefs.profile,
            enteredBy: userToken.getIdentifier()
        )
        try await sendPostRequest(
            Config.uploadPreferencesPath,
            payload: payload
        )
    }

    private struct SettingsPayload: Encodable {
        var report = "settings"
        let settings: FreeAPSSettings?
        let profile: String?
        let enteredBy: String
    }

    func uploadSettings(_ settings: DatabaseSettings) async throws {
        let payload = SettingsPayload(
            settings: settings.settings,
            profile: settings.profile,
            enteredBy: userToken.getIdentifier()
        )
        try await sendPostRequest(
            Config.uploadSettingsPath,
            payload: payload
        )
    }

    private struct PumpSettingsPayload: Encodable {
        var report = "pumpSettings"
        let settings: PumpSettings?
        let profile: String?
        let insulinConcentration: Double?
        let enteredBy: String
    }

    func uploadPumpSettings(_ settings: DatabasePumpSettings) async throws {
        let payload = PumpSettingsPayload(
            settings: settings.settings,
            profile: settings.profile,
            insulinConcentration: settings.insulinConcentration,
            enteredBy: userToken.getIdentifier()
        )
        try await sendPostRequest(
            Config.uploadPumpSettingsPath,
            payload: payload
        )
    }

    private struct TempTargetsPayload: Encodable {
        var report = "tempTargets"
        let tempTargets: [TempTarget]
        let profile: String?
        let enteredBy: String
    }

    func uploadTempTargets(_ targets: DatabaseTempTargets) async throws {
        let payload = TempTargetsPayload(
            tempTargets: targets.tempTargets,
            profile: targets.profile,
            enteredBy: userToken.getIdentifier()
        )
        try await sendPostRequest(
            Config.uploadTempTargetsPath,
            payload: payload
        )
    }

    private struct MealPresetsPayload: JSON {
        var report = "mealPresets"
        var profile: String
        var presets: [MigratedMeals]
        let enteredBy: String
    }

    func uploadMealPresets(_ presets: DatabaseMeal) async throws {
        let payload = MealPresetsPayload(
            profile: presets.profile,
            presets: presets.presets,
            enteredBy: userToken.getIdentifier()
        )
        try await sendPostRequest(
            Config.uploadMealPresetsPath,
            payload: payload
        )
    }

    private struct OverridePayload: JSON {
        var report = "overridePresets"
        var profile: String
        var presets: [MigratedOverridePresets]
        let enteredBy: String
    }

    func uploadOverridePresets(_ presets: DatabaseOverride) async throws {
        let payload = OverridePayload(
            profile: presets.profile,
            presets: presets.presets,
            enteredBy: userToken.getIdentifier()
        )
        try await sendPostRequest(
            Config.uploadOverridePresetsPath,
            payload: payload
        )
    }

    func fetchVersion() async throws -> Version {
        do {
            return try await sendGetRequest(
                Config.versionPath,
                as: Version.self
            )
        } catch {
            warning(.nightscout, "Version fetching error: \(error.localizedDescription)")
            return Version(main: "", dev: "")
        }
    }

    /// Upload the previous day's log file (zlib-compressed) to open-iaps.app.
    func uploadLog(_ logData: Data, logDate: String) async throws {
        guard let compressed = try? (logData as NSData).compressed(using: .zlib) as Data else {
            throw URLError(.cannotCreateFile)
        }

        var request = makeRequest(Config.uploadLogsPath)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.addValue("deflate", forHTTPHeaderField: "Content-Encoding")
        request.addValue(userToken.getIdentifier(), forHTTPHeaderField: "X-App-Id")
        request.addValue(logDate, forHTTPHeaderField: "X-Log-Date")
        request.httpBody = compressed

        // only try once, since it's a large payload; if it fails - it will be retried later
        _ = try await service.runAsync(request, retries: 1)
    }
}

extension Database {
    private func makeRequest(
        _ path: String,
        allowsConstrainedNetworkAccess: Bool = false
    ) -> URLRequest {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = path

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
        return request
    }

    private func makeRequest<Req>(
        _ path: String,
        payload req: Req,
        allowsConstrainedNetworkAccess: Bool = false
    ) -> URLRequest where Req: Encodable {
        var request = makeRequest(path, allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONCoding.encoder.encode(req)

        return request
    }

    private func sendGetRequest<Resp: Decodable>(
        _ path: String,
        as type: Resp.Type,
        allowsConstrainedNetworkAccess: Bool = false
    ) async throws -> Resp {
        let request = makeRequest(path, allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess)
        let data = try await service.runAsync(request, retries: Config.retryCount)
        return try JSONCoding.decoder.decode(type, from: data)
    }

    private func sendPostRequest<Req: Encodable, Resp: Decodable>(
        _ path: String,
        payload req: Req,
        as type: Resp.Type,
        allowsConstrainedNetworkAccess: Bool = false
    ) async throws -> Resp {
        let request = makeRequest(path, payload: req, allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess)
        let data = try await service.runAsync(request, retries: Config.retryCount)
        return try JSONCoding.decoder.decode(type, from: data)
    }

    private func sendPostRequest<Req: Encodable>(
        _ path: String,
        payload req: Req,
    ) async throws {
        let request = makeRequest(path, payload: req)
        _ = try await service.runAsync(request, retries: Config.retryCount)
    }
}
