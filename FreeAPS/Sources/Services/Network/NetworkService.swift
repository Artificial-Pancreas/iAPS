import Combine
import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidResponse
    case badStatusCode(HTTPResponseStatus)
    case badStatus(code: Int, body: Data?) // for async version
    case cancelled
    case zeroRetries

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid HTTP response."
        case let .badStatusCode(code):
            return code.reasonPhrase
        case let .badStatus(code, _): return HTTPURLResponse.localizedString(forStatusCode: code)
        case .cancelled: return "Request cancelled."
        case .zeroRetries: return "Zero retries specified."
        }
    }
}

struct NetworkService {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func run(_ request: URLRequest) -> AnyPublisher<Data, Error> {
        //    debug(.nightscout, "\(request.httpMethod!)  ***\(request.url!.path)\(request.url!.query.map { "?" + $0 } ?? "")")
        session
            .dataTaskPublisher(for: request)
            .tryMap { data, response in
                let code = (response as! HTTPURLResponse).statusCode
                guard 200 ..< 300 ~= code else {
                    throw NetworkError.badStatusCode(.init(statusCode: code))
                }
                return data
            }
            .eraseToAnyPublisher()
    }
}

extension NetworkService {
    /// Run a request and return raw Data. Throws for non-2xx and transport errors.
    func runAsync(_ request: URLRequest, retries: Int = 1) async throws -> Data {
        try await retry(retries) {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                guard 200 ..< 300 ~= http.statusCode else {
                    throw NetworkError.badStatus(code: http.statusCode, body: data)
                }
                return data
            } catch is CancellationError {
                throw NetworkError.cancelled
            } catch {
                throw error
            }
        }
    }

    func decode<T: Decodable>(
        _: T.Type,
        from request: URLRequest,
        decoder: JSONDecoder = JSONCoding.decoder,
        retries: Int = 1
    ) async throws -> T {
        try await decoder.decode(T.self, from: runAsync(request, retries: retries))
    }

    @inline(__always) private func retry<T>(
        _ times: Int,
        _ op: () async throws -> T
    ) async throws -> T {
        for attempt in 0 ... times {
            do {
                return try await op()
            } catch {
                if attempt < times {
                    try? await Task.sleep(for: .milliseconds(200 * (1 << attempt)))
                } else {
                    throw error
                }
            }
        }
        throw NetworkError.zeroRetries
    }
}
