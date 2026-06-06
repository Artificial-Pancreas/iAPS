import Combine
import Foundation

enum NetworkError: Error, LocalizedError {
    case badStatusCode(HTTPResponseStatus, String?)
    case networkError

    var errorDescription: String? {
        switch self {
        case let .badStatusCode(code, _):
            return code.reasonPhrase
        case .networkError:
            return "Network error"
        }
    }

    var errorBody: String? {
        switch self {
        case let .badStatusCode(_, body):
            return body
        case .networkError:
            return nil
        }
    }
}

struct NetworkService {
    func run(_ request: URLRequest) -> AnyPublisher<Data, Error> {
        //    debug(.nightscout, "\(request.httpMethod!)  ***\(request.url!.path)\(request.url!.query.map { "?" + $0 } ?? "")")
        URLSession.shared
            .dataTaskPublisher(for: request)
            .tryMap { data, response in
                let code = (response as! HTTPURLResponse).statusCode
                guard 200 ..< 300 ~= code else {
                    let body = String(data: data, encoding: .utf8)
                    if let body = body {
                        debug(
                            .service,
                            "network client error response for \(request.httpMethod!) \(request.url?.path ?? "--") - status: \(code), body: \(body)"
                        )
                    }
                    throw NetworkError.badStatusCode(.init(statusCode: code), body)
                }
                return data
            }
            .eraseToAnyPublisher()
    }

    private func withRetry<T>(count: Int, _ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for _ in 0 ... count {
            do { return try await operation() } catch { lastError = error }
        }
        throw lastError!
    }

    func runAsync(_ request: URLRequest, retries: Int = 1) async throws -> Data {
        let (data, response) = try await withRetry(count: retries) {
            try await URLSession.shared.data(for: request)
        }
        guard let code = (response as? HTTPURLResponse)?.statusCode else {
            throw NetworkError.networkError
        }
        guard 200 ..< 300 ~= code else {
            let body = String(data: data, encoding: .utf8)
            if let body = body {
                debug(
                    .service,
                    "network client error response for \(request.httpMethod!) \(request.url?.path ?? "--") - status: \(code), body: \(body)"
                )
            }
            throw NetworkError.badStatusCode(.init(statusCode: code), body)
        }
        return data
    }
}
