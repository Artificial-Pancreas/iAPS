import Combine
import SwiftUI
import Swinject

protocol Router {
    var mainModalScreen: CurrentValueSubject<Screen?, Never> { get }
    var mainSecondaryModalView: CurrentValueSubject<AnyView?, Never> { get }
    var alertMessage: PassthroughSubject<String, Never> { get }
    func view(for screen: Screen) -> AnyView
}

final class BaseRouter: Router {
    let mainModalScreen = CurrentValueSubject<Screen?, Never>(nil)
    let mainSecondaryModalView = CurrentValueSubject<AnyView?, Never>(nil)
    let alertMessage = PassthroughSubject<String, Never>()

    private let resolver: Resolver

    init(resolver: Resolver) {
        self.resolver = resolver
    }

    func view(for screen: Screen) -> AnyView {
        screen.view(resolver: resolver).asAny()
    }
}
