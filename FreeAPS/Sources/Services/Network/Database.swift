import Combine
import Foundation

class Database {
    init(token: String) {
        self.token = token
    }

    private enum Config {
        static let sharePath = "/upload.php"
        static let versionPath = "/vcheck.php"
        static let download = "/download.php?token="
        static let profileList = "&section=profile_list"
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
        components.path = Config.download + token + "&section=preferences&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + restoreToken + "&new_token=" + token

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + Config.profileList

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + "&section=settings&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + "&section=profile&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + "&section=profiles_delete&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + "&section=pumpSettings&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + "&section=tempTargets&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + "&section=mealPresets&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.download + token + "&section=overridePresets&profile=" + name

        var request = URLRequest(url: components.url!)
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
        components.path = Config.sharePath

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
        components.path = Config.sharePath

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

    func fetchVersion() -> AnyPublisher<Version, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.versionPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = true
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: Version.self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<Version, Swift.Error> in
                warning(.nightscout, "Version fetching error: \(error.localizedDescription) \(request)")
                return Just(Version(main: "", dev: "")).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func uploadPrefs(_ prefs: NightscoutPreferences) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.sharePath

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
        components.path = Config.sharePath

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
        components.path = Config.sharePath

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
        components.path = Config.sharePath

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
        components.path = Config.sharePath

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
        components.path = Config.sharePath

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
