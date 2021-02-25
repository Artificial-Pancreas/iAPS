import Combine
import LoopKitUI

protocol APSManager {
    func runTest()
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
}
