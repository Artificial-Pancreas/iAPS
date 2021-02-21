import Combine
import RileyLinkBLEKit

class RileyDisplayState: ObservableObject, Identifiable {
    let id: UUID
    let name: String
    let rssi: Int?
    var connected: Bool {
        didSet { didChangeConnection(connected) }
    }

    let didChangeConnection: (Bool) -> Void

    init(id: UUID, name: String, rssi: Int?, connected: Bool, didChangeConnection: @escaping (Bool) -> Void) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.connected = connected
        self.didChangeConnection = didChangeConnection
    }
}

protocol APSManager {
    var rileyDisplayStates: CurrentValueSubject<[RileyDisplayState], Never> { get }
    var deviceProvider: RileyLinkDeviceProvider { get }
    func runTest()
}
