import Foundation
import Swinject

protocol GroupedIssueReporter: IssueReporter {
    func add(reporters: [IssueReporter])
    func remove(reporter: IssueReporter)
}

final class CollectionIssueReporter: GroupedIssueReporter {
    private let reportersLock = NSRecursiveLock(label: "CollectionIssueReporter.reportersLock")
    private var reporters: [IssueReporter] = []

    /// A copy taken under the lock; the reporters run outside it, so a slow reporter never makes
    /// other threads wait to log.
    private var currentReporters: [IssueReporter] {
        reportersLock.perform { reporters }
    }

    func setup() {
        currentReporters.forEach { $0.setup() }
    }

    func setUserIdentifier(_ identifier: String?) {
        currentReporters.forEach { $0.setUserIdentifier(identifier) }
    }

    func reportNonFatalIssue(withName name: String, attributes: [String: String]) {
        currentReporters.forEach { $0.reportNonFatalIssue(withName: name, attributes: attributes) }
    }

    func reportNonFatalIssue(withError error: NSError) {
        currentReporters.forEach { $0.reportNonFatalIssue(withError: error) }
    }

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        currentReporters.forEach { $0.log(category, message, file: file, function: function, line: line) }
    }

    func add(reporters: [IssueReporter]) {
        reportersLock.perform {
            self.reporters.append(contentsOf: reporters)
        }
    }

    func remove(reporter: IssueReporter) {
        reportersLock.perform {
            reporters.removeAll { $0 === reporter }
        }
    }
}
