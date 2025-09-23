import Combine
import Foundation

enum NetworkError: Error, LocalizedError {
    case badStatusCode(HTTPResponseStatus)

    var errorDescription: String? {
        switch self {
        case let .badStatusCode(code):
            return code.reasonPhrase
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
                    if let body = String(data: data, encoding: .utf8) {
                        debug(
                            .nightscout,
                            "network client error response for \(request.httpMethod!) \(request.url) - status: \(code), body: \(body)"
                        )
                    }
                    throw NetworkError.badStatusCode(.init(statusCode: code))
                }
                return data
            }
            .eraseToAnyPublisher()
    }
}
