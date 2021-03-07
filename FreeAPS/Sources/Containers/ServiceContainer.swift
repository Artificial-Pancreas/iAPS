import Foundation
import Swinject

private let resolver = FreeAPSApp.resolver

enum ServiceContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(NotificationCenter.self) { _ in Foundation.NotificationCenter.default }
        container.register(Broadcaster.self) { _ in BaseBroadcaster() }
        container.register(GroupedIssueReporter.self) { _ in CollectionIssueReporter() }
    }
}
