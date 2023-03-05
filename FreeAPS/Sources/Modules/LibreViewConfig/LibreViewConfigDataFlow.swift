import Combine
import Foundation

enum LibreViewConfig {
    enum Config {
        static let lvLoginKey = "LibreViewConfig.login"
        static let lvPasswordKey = "LibreViewConfig.password"
        static let lvTokenKey = "LibreViewConfig.token"
    }

    enum Server: String, CaseIterable {
        case custom
        case ru = "api.libreview.ru"
        case eu = "api-eu.libreview.io"
        case us = "api-us.libreview.io"
        case de = "api-de.libreview.io"
        case fr = "api-fr.libreview.io"
        case jp = "api-jp.libreview.io"
        case ap = "api-ap.libreview.io"
        case au = "api-au.libreview.io"
        case ae = "api-ae.libreview.io"

        static func byViewTag(_ tag: Int) -> Self? {
            switch tag {
            case 0: return .custom
            case 1: return .ru
            case 2: return .eu
            case 3: return .us
            case 4: return .de
            case 5: return .fr
            case 6: return .jp
            case 7: return .ap
            case 8: return .au
            case 9: return .ae
            default: return nil
            }
        }
    }

    enum UploadsFrequency: Int, CaseIterable {
        case randomUpTo4Hours = 0
        case eachLoop
        case minutes15
        case minutes30
        case hour1
        case hour4

        var description: String {
            switch self {
            case .eachLoop: return NSLocalizedString("Each Loop", comment: "")
            case .minutes15: return NSLocalizedString("Every 15 minutes", comment: "")
            case .minutes30: return NSLocalizedString("Every 30 minutes", comment: "")
            case .hour1: return NSLocalizedString("Every hour", comment: "")
            case .hour4: return NSLocalizedString("Every 4 hours", comment: "")
            case .randomUpTo4Hours: return NSLocalizedString(
                    "Random upload, but less than 4 hours after the last one",
                    comment: ""
                )
            }
        }

        var secondsToNextUpload: Double {
            switch self {
            case .eachLoop: return 0
            case .minutes15: return 900
            case .minutes30: return 1800
            case .hour1: return 3600
            case .hour4: return 14400
            case .randomUpTo4Hours: return Double(Int.random(in: 0 ... 14400))
            }
        }
    }
}

protocol LibreViewConfigProvider: Provider {
    func createConnection(url: URL, username: String, password: String) -> AnyPublisher<LibreLinkToken, Error>
}
