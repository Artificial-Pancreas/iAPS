import Foundation
import Moya

enum RemoteService {
    case login
    case upload(classifier: String, id: String, image: Data)
}

extension RemoteService: TargetType {
    var baseURL: URL { URL(string: "http://94.141.168.254:8080")! }

    var path: String {
        switch self {
        case .login:
            return "login"
        case .upload:
            return "upload"
        }
    }

    var method: Moya.Method {
        switch self {
        case .login:
            return .post
        case .upload:
            return .post
        }
    }

    var sampleData: Data {
        Data()
    }

    var task: Task {
        switch self {
        case .login:
            return .requestPlain
        case let .upload(classifier, id, image):
            return .uploadMultipart(
                [
                    .init(provider: .data(classifier.data(using: .utf8)!), name: "classifier"),
                    .init(provider: .data(id.data(using: .utf8)!), name: "id"),
                    .init(
                        provider: .data(image),
                        name: "image",
                        fileName: "image.jpeg",
                        mimeType: "image/jpeg"
                    )
                ]
            )
        }
    }

    var headers: [String: String]? {
        switch self {
        case .login:
            return ["Content-type": "application/json"]
        case .upload:
            return ["Content-type": "multipart/form-data"]
        }
    }
}
