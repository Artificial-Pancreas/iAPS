import Combine
import LoopKitUI

protocol APSManager {
    func runTest()
    func makeProfiles()
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    func fetchLastGlucose()
    func makeMeal()
}
