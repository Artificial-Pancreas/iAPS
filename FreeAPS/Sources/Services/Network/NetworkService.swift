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
        debug(.nightscout, "Request at \(request.url!.absoluteString)")
        return URLSession.shared
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
