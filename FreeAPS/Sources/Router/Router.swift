import Combine
import SwiftUI
import Swinject

enum MessageType {
    case info
    case warning
    case errorPump
}

struct MessageContent {
    var content: String
    var type: MessageType = .info
}

@MainActor protocol Router: Sendable {
    var mainModalScreen: CurrentValueSubject<Screen?, Never> { get }
    var mainSecondaryModalView: CurrentValueSubject<AnyView?, Never> { get }
    func view(for screen: Screen) -> AnyView
}

@MainActor final class BaseRouter: Router {
    let mainModalScreen = CurrentValueSubject<Screen?, Never>(nil)
    let mainSecondaryModalView = CurrentValueSubject<AnyView?, Never>(nil)

    nonisolated(unsafe) private let resolver: Resolver

    nonisolated init(resolver: Resolver) {
        self.resolver = resolver
    }

    func view(for screen: Screen) -> AnyView {
        screen.view(resolver: resolver).asAny()
    }
}
