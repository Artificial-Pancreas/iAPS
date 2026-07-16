import Foundation

typealias ReachabilityStatus = NetworkReachabilityManager.NetworkReachabilityStatus
typealias Listener = NetworkReachabilityManager.Listener

protocol ReachabilityManager: AnyObject, Sendable {
    var status: ReachabilityStatus { get }
    var isReachable: Bool { get }
    func startListening(onQueue: DispatchQueue, onUpdatePerforming: @escaping Listener) -> Bool
    func stopListening()
}

// @unchecked Sendable is safe here: all mutable state is gated behind @Protected (UnfairLock)
extension NetworkReachabilityManager: ReachabilityManager, @unchecked Sendable {}

extension ReachabilityStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .notReachable:
            return "NOT reachable"
        case let .reachable(connectionType):
            return "reachable by " + (connectionType == .cellular ? "Cellular" : "WiFi")
        }
    }
}
