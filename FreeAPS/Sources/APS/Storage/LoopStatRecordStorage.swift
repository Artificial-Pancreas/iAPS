import CoreData
import Foundation
import Swinject

final class LoopStatRecordStorage: LifetimeOwner, AppService {
    enum Config {
        /// how far back the gaps are looked for
        static let historyWindow: TimeInterval = .hours(26)
    }

    private let coreDataStorage = CoreDataStorage()
    private let appCoordinator: AppCoordinator

    let lifetime = Lifetime()

    init(resolver: Resolver) {
        appCoordinator = resolver.resolve(AppCoordinator.self)!
    }

    // this is called at the start of the app
    func start() async {
        await publishLoopGaps()

        observe(appCoordinator.loopCompleted) { me, _ in
            await me.publishLoopGaps()
        }

        observe(appCoordinator.appBecomeActiveEvents) { me, _ in
            await me.publishLoopGaps()
        }

        observe(
            appCoordinator.settings
                .map(\.allowOneMinuteLoop)
                .removeDuplicates()
                .dropFirst()
        ) { me, _ in
            await me.publishLoopGaps()
        }
    }

    private func publishLoopGaps() async {
        let loopStarts = await coreDataStorage.fetchLoopStarts(
            interval: Date.now.subtractingTimeInterval(Config.historyWindow) as NSDate
        )

        // detect() returns oldest -> newest
        let gaps: [LoopGap] = LoopGap.detect(
            in: loopStarts,
            allowOneMinuteLoop: appCoordinator.settings.value.allowOneMinuteLoop
        ).reversed()

        guard gaps != appCoordinator.loopGaps.value else { return }

        appCoordinator.setLoopGaps(gaps)
    }

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
