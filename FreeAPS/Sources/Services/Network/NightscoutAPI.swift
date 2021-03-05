import Combine
import CommonCrypto
import Foundation

class NightscoutAPI {
    init(url: URL, secret: String? = nil) {
        self.url = url
        self.secret = secret
    }

    private enum Config {
        static let entriesPath = "/api/v1/entries/sgv.json"
        static let treatmentsPath = "/api/v1/treatments.json"
        static let retryCount = 2
        static let timeout: TimeInterval = 2
    }

    enum Error: LocalizedError {
        case badStatusCode
        case missingURL
    }

    let url: URL
    let secret: String?

    private let service = NetworkService()
}

extension NightscoutAPI {
    func checkConnection() -> AnyPublisher<Void, Swift.Error> {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "feeaps-x://"
            var notes = "FreeAPS X connected"
        }
        let check = Check()
        var request = URLRequest(url: url.appendingPathComponent(Config.treatmentsPath))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONEncoder().encode(check)
        return service.run(request)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchLastGlucose(_ count: Int, sinceDate: Date? = nil) -> AnyPublisher<[BloodGlucose], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.entriesPath
        components.queryItems = [URLQueryItem(name: "count", value: "\(count)")]
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
            .map {
                $0.filter { $0.isStateValid }
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
            URLQueryItem(name: "find[enteredBy][$ne]", value: CarbsEntry.manual)
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
            .decode(type: [CarbsEntry].self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func fetchTempTargets(sinceDate: Date? = nil) -> AnyPublisher<[TempTarget], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [URLQueryItem(name: "find[eventType]", value: "Temporary+Target")]
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
            .decode(type: [TempTarget].self, decoder: JSONCoding.decoder)
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
