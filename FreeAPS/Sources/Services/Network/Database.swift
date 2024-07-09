import Combine
import Foundation

class Database {
    init(token: String) {
        self.token = token
    }

    private enum Config {
        static let sharePath = "/upload.php"
        static let versionPath = "/vcheck.php"
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
        components.path = "/download.php?token=" + token + "&section=preferences&profile=" + name

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = true
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: Preferences.self, decoder: JSONCoding.decoder)
            /* .catch { error -> AnyPublisher<Preferences, Swift.Error> in
                 warning(.nightscout, "Preferences fetching error: \(error.localizedDescription) \(request)")
                 return Just(Preferences()).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
             } */
            .eraseToAnyPublisher()
    }

    func fetchSettings(_ name: String) -> AnyPublisher<FreeAPSSettings, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/download.php?token=" + token + "&section=settings&profile=" + name

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = true
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
        components.path = "/download.php?token=" + token + "&section=profile&profile=" + name

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: NightscoutProfileStore.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func fetchPumpSettings(_ name: String) -> AnyPublisher<PumpSettings, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/download.php?token=" + token + "&section=pumpSettings&profile=" + name

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
        components.path = "/download.php?token=" + token + "&section=tempTargets&profile=" + name

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = true
        request.timeoutInterval = Config.timeout

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: DatabaseTempTargets.self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func uploadSettingsToDatabase(_ profile: NightscoutProfileStore) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.sharePath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
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
        request.allowsConstrainedNetworkAccess = false
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
        request.allowsConstrainedNetworkAccess = false
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
        request.allowsConstrainedNetworkAccess = false
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
        request.allowsConstrainedNetworkAccess = false
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
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(targets)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
