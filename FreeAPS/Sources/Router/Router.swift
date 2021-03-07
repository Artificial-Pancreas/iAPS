import Combine
import SwiftUI
import Swinject

protocol Router {
    var mainModalScreen: CurrentValueSubject<Screen?, Never> { get }
    var alertMessage: PassthroughSubject<String, Never> { get }
    func view(for screen: Screen) -> AnyView
}

final class BaseRouter: Router {
    let mainModalScreen = CurrentValueSubject<Screen?, Never>(nil)
    let alertMessage = PassthroughSubject<String, Never>()

    private let resolver: Resolver

    private var screens: [Screen.ID: AnyView] = [:]

    init(resolver: Resolver) {
        self.resolver = resolver
    }

    func view(for screen: Screen) -> AnyView {
        if let view = screens[screen.id] {
            return view
        }
        screens[screen.id] = screen.view(resolver: resolver).asAny()
        return screens[screen.id]!
    }
}
