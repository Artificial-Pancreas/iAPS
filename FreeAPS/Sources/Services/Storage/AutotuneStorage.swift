import Foundation
import LoopKit
import Swinject

protocol AutotuneStorage: AnyObject, Sendable {
    var autotune: Profile? { get async }
    func updateAutotune(_ autotune: Profile?) async

    func resetCache() async
}

actor BaseAutotuneStorage: AutotuneStorage, AppService {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called on app start, before anything is rendered
    func start() async {
        await resetCache()
    }

    func resetCache() async {
        appCoordinator.setAutotune(await self.autotune)
    }

    var autotune: Profile? {
        get async {
            await storage.retrieve(OpenAPS.Settings.autotune, as: Profile.self)
        }
    }

    func updateAutotune(_ autotune: Profile?) async {
        if let autotune {
            await self.storage.save(autotune, as: OpenAPS.Settings.autotune)
        } else {
            await self.storage.remove(OpenAPS.Settings.autotune)
        }
        appCoordinator.setAutotune(autotune)
    }
}
