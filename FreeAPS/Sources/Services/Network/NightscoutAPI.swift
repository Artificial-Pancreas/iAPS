import Combine
import CommonCrypto
import Foundation

class NightscoutAPI {
    init(url: URL, secret: String? = nil) {
        self.url = url
        self.secret = secret
    }

    private enum Config {
        static let entriesPath = "/api/v1/entries.json"
        static let retryCount = 5
    }

    enum Error: LocalizedError {
        case badStatusCode
        case missingURL
    }

    let url: URL
    let secret: String?

    private let service = NetworkService()

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

extension NightscoutAPI {
    func checkConnection() -> AnyPublisher<Void, Swift.Error> {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "feeaps-x://"
            var notes = "FreeAPS X connected"
        }
        let check = Check()
        var request = URLRequest(url: url.appendingPathComponent("api/v1/treatments.json"))
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

    func fetchLast(_ count: Int) -> AnyPublisher<[BloodGlucose], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.entriesPath
        components.queryItems = [URLQueryItem(name: "count", value: "\(count)")]

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false

        return URLSession.shared.dataTaskPublisher(for: request)
            .retry(Config.retryCount)
            .tryMap { output in
                guard let response = output.response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw Error.badStatusCode
                }
                return output.data
            }
            .decode(type: [BloodGlucose].self, decoder: decoder)
            .map { $0.filter { $0.isStateValid } }
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
