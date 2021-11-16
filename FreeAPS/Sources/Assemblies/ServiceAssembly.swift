import Foundation
import Swinject

final class ServiceAssembly: Assembly {
    func assemble(container: Container) {
        container.register(NotificationCenter.self) { _ in Foundation.NotificationCenter.default }
        container.register(Broadcaster.self) { _ in BaseBroadcaster() }
        container.register(GroupedIssueReporter.self) { _ in
            let reporter = CollectionIssueReporter()
            reporter.add(reporters: [
                SimpleLogReporter()
            ])
            reporter.setup()
            return reporter
        }
        container.register(CalendarManager.self) { r in BaseCalendarManager(resilver: r) }
    }
}
