import Combine
import CommonCrypto
import Foundation
import JavaScriptCore
import Swinject

class NightscoutAPI {
    init(url: URL, secret: String? = nil) {
        self.url = url
        self.secret = secret?.nonEmpty
    }

    private enum Config {
        static let entriesPath = "/api/v1/entries/sgv.json"
        static let uploadEntriesPath = "/api/v1/entries.json"
        static let treatmentsPath = "/api/v1/treatments.json"
        static let statusPath = "/api/v1/devicestatus.json"
        static let profilePath = "/api/v1/profile.json"
        static let sharePath = "/upload.php"
        static let versionPath = "/vcheck.php"
        static let retryCount = 2
        static let timeout: TimeInterval = 60
    }

    enum Error: LocalizedError {
        case badStatusCode
        case missingURL
    }

    let url: URL
    let secret: String?

    private let service = NetworkService()

    @Injected() private var settingsManager: SettingsManager!
}

extension NightscoutAPI {
    func checkConnection() -> AnyPublisher<Void, Swift.Error> {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "iAPS"
            var notes = "iAPS connected"
        }
        let check = Check()
        var request = URLRequest(url: url.appendingPathComponent(Config.treatmentsPath))

        if let secret = secret {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            request.httpBody = try! JSONCoding.encoder.encode(check)
        } else {
            request.httpMethod = "GET"
        }

        return service.run(request)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchLastGlucose(sinceDate: Date? = nil) -> AnyPublisher<[BloodGlucose], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.entriesPath
        components.queryItems = [URLQueryItem(name: "count", value: "\(1600)")]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[dateString][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [BloodGlucose].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[BloodGlucose], Swift.Error> in
                warning(.nightscout, "Glucose fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .map { glucose in
                glucose
                    .map {
                        var reading = $0
                        reading.glucose = $0.sgv
                        return reading
                    }
            }
            .eraseToAnyPublisher()
    }

    func fetchCarbs(sinceDate: Date? = nil) -> AnyPublisher<[CarbsEntry], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.trio.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [CarbsEntry].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[CarbsEntry], Swift.Error> in
                warning(.nightscout, "Carbs fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func deleteCarbs(_ date: Date) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath

        let arguments = "find[creation_date][$eq]"
        let value = Formatter.iso8601withFractionalSeconds.string(from: date)

        components.queryItems = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: arguments,
                value: value
            )
        ]

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteManualGlucose(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[glucose][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteInsulin(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[bolus][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchTempTargets(sinceDate: Date? = nil) -> AnyPublisher<[TempTarget], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Temporary+Target"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: TempTarget.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(name: "find[duration][$exists]", value: "true")
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [TempTarget].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[TempTarget], Swift.Error> in
                warning(.nightscout, "TempTarget fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func fetchAnnouncement(sinceDate: Date? = nil) -> AnyPublisher<[Announcement], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Announcement"),
            URLQueryItem(
                name: "find[enteredBy]",
                value: Announcement.remote.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [Announcement].self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func deleteAnnouncements() -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Announcement"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds
                    .string(from: Date.now)
            )
        ]
        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteNSoverride() -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Exercise"),
            URLQueryItem(name: "count", value: "\(1)"), // Delete latest
            URLQueryItem(name: "find[enteredBy]", value: "iAPS") // Don't delete entries created in NS
        ]
        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteOverride(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[Exercise][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]
        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    // Dev work. Delete all exercise events
    func deleteAllNSoverrrides() -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Exercise")
        ]
        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadTreatments(_ treatments: [NigtscoutTreatment]) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try? JSONCoding.encoder.encode(treatments)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadEcercises(_ override: [NigtscoutExercise]) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try? JSONCoding.encoder.encode(override)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadGlucose(_ glucose: [BloodGlucose]) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadEntriesPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(glucose)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadStats(_ stats: NightscoutStatistics) -> AnyPublisher<Void, Swift.Error> {
        let statURL = IAPSconfig.statURL
        var components = URLComponents()
        components.scheme = statURL.scheme
        components.host = statURL.host
        components.port = statURL.port
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
        let statURL = IAPSconfig.statURL
        var components = URLComponents()
        components.scheme = statURL.scheme
        components.host = statURL.host
        components.port = statURL.port
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

    func uploadStatus(_ status: NightscoutStatus) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.statusPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(status)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadPrefs(_ prefs: NightscoutPreferences) -> AnyPublisher<Void, Swift.Error> {
        let statURL = IAPSconfig.statURL
        var components = URLComponents()
        components.scheme = statURL.scheme
        components.host = statURL.host
        components.port = statURL.port
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
        let statURL = IAPSconfig.statURL
        var components = URLComponents()
        components.scheme = statURL.scheme
        components.host = statURL.host
        components.port = statURL.port
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

    func uploadProfile(_ profile: NightscoutProfileStore) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.profilePath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(profile)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadSettingsToDatabase(_ profile: NightscoutProfileStore) -> AnyPublisher<Void, Swift.Error> {
        let statURL = IAPSconfig.statURL
        var components = URLComponents()
        components.scheme = statURL.scheme
        components.host = statURL.host
        components.port = statURL.port
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

    func uploadPreferences(_ preferences: Preferences) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.profilePath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(preferences)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

private extension String {
    func sha1() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}
