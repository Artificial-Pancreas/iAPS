import LoopKit
import MinimedKit
import RileyLinkBLEKit
import RileyLinkKit
import Swinject

final class BaseAPSManager: APSManager, Injectable {
    private var openAPS: OpenAPS!
    @Injected() var deviceDataManager: DeviceDataManager!

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: resolver.resolve(FileStorage.self)!)
    }

    func runTest() {
        openAPS.test()
    }
}
