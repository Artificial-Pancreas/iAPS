import Combine
import Foundation
import Moya

protocol NetworkManager {
    func upload(classifier: String, id: String, image: Data) -> AnyPublisher<HTTPResponseStatus?, MoyaError>
}

final class BaseNetworkManager: NetworkManager {
    private let remote = MoyaProvider<RemoteService>()

    func upload(classifier: String, id: String, image: Data) -> AnyPublisher<HTTPResponseStatus?, MoyaError> {
        Deferred {
            Future<Response, MoyaError> { promise in
                self.remote.request(
                    .upload(
                        classifier: classifier,
                        id: id,
                        image: image
                    ),
                    completion: promise
                )
            }
            .map { $0.response.flatMap { HTTPResponseStatus(statusCode: $0.statusCode) } }
        }.eraseToAnyPublisher()
    }
}
