import Combine
import Foundation
import LoopKitUI
import Swinject

final class BaseAPSManager: APSManager, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistory: PumpHistoryStorage!
    @Injected() private var keychain: Keychain!
    @Injected() private var deviceDataManager: DeviceDataManager!
    private var openAPS: OpenAPS!

    private var glucoseCancellable: AnyCancellable?

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
        openAPS = OpenAPS(storage: storage)
    }

    func runTest() {
        openAPS.test()
    }

    func makeProfiles() {
        openAPS.makeProfile(autotuned: false)
        openAPS.makeProfile(autotuned: true)
    }

    func makeMeal() {
        openAPS.makeClock()
        openAPS.makeMeal()
    }

    func fetchLastGlucose() {
        if let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
           let url = URL(string: urlString)
        {
            glucoseCancellable = NightscoutAPI(url: url).fetchLast(288)
                .sink { _ in }
            receiveValue: { glucose in
                try? self.storage.append(glucose, to: OpenAPS.Monitor.glucose, uniqBy: \.date)
            }
        }
    }
}
