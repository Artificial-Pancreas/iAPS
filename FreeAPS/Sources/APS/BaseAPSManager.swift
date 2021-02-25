import Combine
import Foundation
import LoopKitUI
import Swinject

final class BaseAPSManager: APSManager, Injectable {
    private var openAPS: OpenAPS!
    private let deviceDataManager = DeviceDataManager()

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
        openAPS = OpenAPS(storage: resolver.resolve(FileStorage.self)!)
    }

    func runTest() {
        openAPS.test()
    }
}
