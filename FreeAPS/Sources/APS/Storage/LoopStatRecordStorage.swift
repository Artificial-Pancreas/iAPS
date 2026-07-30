import CoreData
import Foundation
import Swinject

final class LoopStatRecordStorage: LifetimeOwner, AppService {
    private let coreDataStorage = CoreDataStorage()
    private let appCoordinator: AppCoordinator

    let lifetime = Lifetime()

    init(resolver: Resolver) {
        appCoordinator = resolver.resolve(AppCoordinator.self)!
    }

    // this is called at the start of the app
    func start() async {}

    func persistLoopStats(loopStatRecord: LoopStats, error: String?) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { coredataContext in
            let nLS = LoopStatRecord(context: coredataContext)
            nLS.start = loopStatRecord.start
            nLS.end = loopStatRecord.end ?? Date()
            nLS.loopStatus = loopStatRecord.loopStatus
            nLS.duration = loopStatRecord.duration ?? 0.0
            nLS.interval = loopStatRecord.interval ?? 0.0
            if let error = error {
                nLS.error = error
            }
            try? coredataContext.save()
        }
    }
}
