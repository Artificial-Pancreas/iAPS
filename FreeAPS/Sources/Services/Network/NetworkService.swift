import Combine
import Foundation

enum NetworkError: Error, LocalizedError {
    case badStatusCode(HTTPResponseStatus, String?)

    var errorDescription: String? {
        switch self {
        case let .badStatusCode(code, _):
            return code.reasonPhrase
        }
    }

    var errorBody: String? {
        switch self {
        case let .badStatusCode(_, body):
            return body
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
}
