import Combine
import SwiftUI
import Swinject

protocol Router {
    var selectTab: PassthroughSubject<Int, Never> { get }
    var modalScreen: CurrentValueSubject<Screen?, Never> { get }
    var tabs: [Screen] { get }
    func view(for screen: Screen) -> AnyView
}

final class BaseRouter: Router {
    let selectTab = PassthroughSubject<Int, Never>()
    let modalScreen = CurrentValueSubject<Screen?, Never>(nil)

    private let resolver: Resolver

    let tabs: [Screen] = [
        .home,
        .settings
    ]

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
