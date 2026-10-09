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
    /// Set for a device alert, so dismissing the message acknowledges it. Nil for plain info messages
    /// (logging, Garmin), which have nothing to acknowledge.
    var alertIdentity: AlertIdentity? = nil
    /// The device's own label for its acknowledge action ("OK"), so the card's button says what the
    /// device would say. `Alert.Content.acknowledgeActionButtonLabel`.
    var acknowledgeButtonLabel: String? = nil
}

/// Showing and taking down a message share one channel so they stay in order. On separate streams a
/// quick issue -> retract could deliver the dismissal first and leave the retracted alert on screen
/// for good.
enum AlertMessage {
    case show(MessageContent)
    /// The alert is over - retracted by the device, or acknowledged somewhere else.
    case dismiss(AlertIdentity)
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
