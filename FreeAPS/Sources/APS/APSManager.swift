import Combine
import LoopKitUI

protocol APSManager {
    func runTest()
    func setPumpManager(_: PumpManagerUI)
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
}
