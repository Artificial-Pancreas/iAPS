import Combine
import CommonCrypto
import Foundation

struct NightscoutAPI {
    let url: URL
    let secret: String
    private let service = NetworkService()
}

extension NightscoutAPI {
    func checkConnection() -> AnyPublisher<Void, Error> {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "feeaps-x://"
            var notes = "FreeAPS connected"
        }
        let check = Check()
        var request = URLRequest(url: url.appendingPathComponent("api/v1/treatments.json"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        request.httpBody = try! JSONEncoder().encode(check)
        return service.run(request)
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
