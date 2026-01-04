import Foundation
import Network

/// Network quality monitor for determining analysis strategy
class NetworkQualityMonitor: ObservableObject {
    static let shared = NetworkQualityMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var isExpensive = false
    @Published var isConstrained = false

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.global().async { [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained

                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wiredEthernet
                } else {
                    self?.connectionType = nil
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Determines if we should use aggressive optimizations
    var shouldUseConservativeMode: Bool {
        !isConnected || isExpensive || isConstrained || connectionType == .cellular
    }

    /// Determines if parallel processing is safe
    var shouldUseParallelProcessing: Bool {
        isConnected && !isExpensive && !isConstrained && connectionType == .wifi
    }

    /// Gets appropriate timeout for current network conditions
    var recommendedTimeout: TimeInterval {
        if shouldUseConservativeMode {
            return 45.0 // Conservative timeout for poor networks
        } else {
            return 25.0 // Standard timeout for good networks
        }
    }
}
