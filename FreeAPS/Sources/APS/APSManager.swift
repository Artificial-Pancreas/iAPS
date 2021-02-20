import Combine
import RileyLinkBLEKit

struct RileyDisplayState: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int?
    let connected: Bool
}

protocol APSManager {
    var rileyDisplayStates: CurrentValueSubject<[RileyDisplayState], Never> { get }
    func runTest()
}
