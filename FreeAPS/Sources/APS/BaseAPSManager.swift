import Combine
import Foundation
import LoopKitUI
import Swinject

final class BaseAPSManager: APSManager, Injectable {
    @Injected() var storage: FileStorage!
    private var openAPS: OpenAPS!
    private var deviceDataManager: DeviceDataManager!

    var pumpManager: PumpManagerUI? {
        get {
            deviceDataManager.pumpManager
        }
        set {
            deviceDataManager.pumpManager = newValue
        }
    }

    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { deviceDataManager.pumpDisplayState }

    init(resolver: Resolver) {
        injectServices(resolver)
        deviceDataManager = DeviceDataManager(storage: storage)
        openAPS = OpenAPS(storage: storage)
    }

    func runTest() {
        openAPS.test()
    }
}
