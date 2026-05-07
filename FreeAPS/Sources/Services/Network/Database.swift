import Combine
import Foundation

class Database {
    init(token: String) {
        self.token = token
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

        static let retryCount = 2
        static let timeout: TimeInterval = 60
    }

    let url: URL = IAPSconfig.statURL
    let token: String

    private let service = NetworkService()
}

extension Database {
    func fetchPreferences(_ name: String) -> AnyPublisher<Preferences, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadPreferencesPath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: Preferences.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func moveProfiles(token: String, restoreToken: String) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadRestorePath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "restore_token": restoreToken])
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchProfiles() -> AnyPublisher<ProfileList, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadListPath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token])
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: ProfileList.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func fetchSettings(_ name: String) -> AnyPublisher<FreeAPSSettings, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadSettingsPath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.timeoutInterval = Config.timeout

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: FreeAPSSettings.self, decoder: decoder)
            .eraseToAnyPublisher()
    }

    func fetchProfile(_ name: String) -> AnyPublisher<NightscoutProfileStore, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadProfilePath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: NightscoutProfileStore.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func deleteProfile(_ name: String) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadDeletePath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchPumpSettings(_ name: String) -> AnyPublisher<PumpSettings, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadPumpSettingsPath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.allowsConstrainedNetworkAccess = true
        request.timeoutInterval = Config.timeout

        let decoder = JSONDecoder()

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: PumpSettings.self, decoder: decoder)
            .eraseToAnyPublisher()
    }

    func fetchTempTargets(_ name: String) -> AnyPublisher<DatabaseTempTargets, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadTempTargetsPath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.allowsConstrainedNetworkAccess = true
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: DatabaseTempTargets.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func fetchMealPressets(_ name: String) -> AnyPublisher<MealDatabase, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadMealPresetsPath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: MealDatabase.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func fetchOverridePressets(_ name: String) -> AnyPublisher<OverrideDatabase, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.downloadOverridePresetsPath

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["token": token, "profile": name])
        request.allowsConstrainedNetworkAccess = true
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: OverrideDatabase.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func uploadSettingsToDatabase(_ profile: NightscoutProfileStore) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadProfilesPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(profile)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadStats(_ stats: NightscoutStatistics) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadStatisticsPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONCoding.encoder.encode(stats)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadPrefs(_ prefs: NightscoutPreferences) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadPreferencesPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(prefs)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadSettings(_ settings: NightscoutSettings) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadSettingsPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(settings)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadPumpSettings(_ settings: DatabasePumpSettings) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadPumpSettingsPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(settings)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadTempTargets(_ targets: DatabaseTempTargets) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadTempTargetsPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(targets)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadMealPresets(_ presets: MealDatabase) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadMealPresetsPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(presets)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploaOverrridePresets(_ presets: OverrideDatabase) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadOverridePresetsPath

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(presets)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    private func migrateMealPresets() -> [MigratedMeals] {
        let meals = CoreDataStorage().fetchMealPresets()
        return meals.map({ item -> MigratedMeals in
            MigratedMeals(
                carbs: (item.carbs ?? 0) as Decimal,
                dish: item.dish ?? "",
                fat: (item.fat ?? 0) as Decimal,
                protein: (item.protein ?? 0) as Decimal
            )
        })
    }

    private func migrateOverridePresets() -> [MigratedOverridePresets] {
        let presets = OverrideStorage().fetchProfiles()
        return presets.map({ item -> MigratedOverridePresets in
            MigratedOverridePresets(
                advancedSettings: item.advancedSettings,
                cr: item.cr,
                date: item.date ?? Date(),
                duration: (item.duration ?? 0) as Decimal,
                emoji: item.emoji ?? "",
                end: (item.end ?? 0) as Decimal,
                id: item.id ?? "",
                indefininite: item.indefinite,
                isf: item.isf,
                isndAndCr: item.isfAndCr, basal: item.basal,
                maxIOB: (item.maxIOB ?? 0) as Decimal,
                name: item.name ?? "",
                overrideMaxIOB: item.overrideMaxIOB,
                percentage: item.percentage,
                smbAlwaysOff: item.smbIsAlwaysOff,
                smbIsOff: item.smbIsOff,
                smbMinutes: (item.smbMinutes ?? 0) as Decimal,
                start: (item.start ?? 0) as Decimal,
                target: (item.target ?? 0) as Decimal,
                uamMinutes: (item.uamMinutes ?? 0) as Decimal
            )

        })
    }

    func mealPresetDatabaseUpload(profile: String, token: String) -> MealDatabase {
        MealDatabase(profile: profile, presets: migrateMealPresets(), enteredBy: token)
    }

    func overridePresetDatabaseUpload(profile: String, token: String) -> OverrideDatabase {
        OverrideDatabase(profile: profile, presets: migrateOverridePresets(), enteredBy: token)
    }
}
