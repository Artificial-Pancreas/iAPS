import Foundation
import LoopKitUI
import SwiftDate
import Swinject

extension Home {
    final class Provider: HomeProvider, Sendable {
        private let storage: FileStorage
        private let appCoordinator: AppCoordinator
        private let apsManager: APSManager
        private let glucoseStorage: GlucoseStorage
        private let pumpHistoryStorage: PumpHistoryStorage
        private let tempTargetsStorage: TempTargetsStorage
        private let carbsStorage: CarbsStorage
        private let announcementStorage: AnnouncementsStorage

        let overrideStorage: OverrideStorage
        let coreDateStorage = CoreDataStorage()

        required init(resolver: Resolver) {
            storage = resolver.resolve(FileStorage.self)!
            appCoordinator = resolver.resolve(AppCoordinator.self)!
            apsManager = resolver.resolve(APSManager.self)!
            glucoseStorage = resolver.resolve(GlucoseStorage.self)!
            pumpHistoryStorage = resolver.resolve(PumpHistoryStorage.self)!
            tempTargetsStorage = resolver.resolve(TempTargetsStorage.self)!
            carbsStorage = resolver.resolve(CarbsStorage.self)!
            announcementStorage = resolver.resolve(AnnouncementsStorage.self)!
            overrideStorage = resolver.resolve(OverrideStorage.self)!
        }

        func fetchedMeals(_ interval: NSDate) async -> [MealsSnapshot] {
            await coreDateStorage.fetchMealData(
                interval: interval
            )
        }

        func overrideHistory() async -> [OverrideHistorySnapshot] {
            await overrideStorage.fetchOverrideHistory(interval: DateFilter.day.startDate)
        }

        func reasons() async -> [IOBData]? {
            let reasons = await coreDateStorage.fetchReasons(interval: DateFilter.day.startDate)

            guard reasons.count > 3 else {
                return nil
            }

            return reasons.compactMap {
                entry -> IOBData in
                IOBData(
                    date: entry.date ?? Date(),
                    iob: (entry.iob ?? 0) as Decimal,
                    cob: (entry.cob ?? 0) as Decimal
                )
            }
        }

        func heartbeatNow() {
            appCoordinator.sendHeartbeat()
        }

        func smoothedGlucose(hours: Int) -> [BloodGlucose] {
            let now = Date()
            // reverse to oldest->newest order
            return appCoordinator.glucoseSmoothed.value.reversed().filter {
                $0.dateString.addingTimeInterval(.hours(hours)) > now
            }
        }

        func rawGlucose(hours: Int) -> [BloodGlucose] {
            let now = Date()
            // reverse to oldest->newest order
            return appCoordinator.glucoseRaw.value.reversed().filter {
                $0.dateString.addingTimeInterval(.hours(hours)) > now
            }
        }

        func manualGlucose(hours: Int) -> [BloodGlucose] {
            let now = Date()
            // reverse to oldest->newest order
            return appCoordinator.glucoseSmoothed.value.reversed().filter {
                $0.type == GlucoseType.manual.rawValue &&
                    $0.dateString.addingTimeInterval(.hours(hours)) > now
            }
        }

        func carbs(hours: Int) -> [CarbsEntry] {
            let now = Date()
            return appCoordinator.carbHistory.value.filter {
                $0.createdAt.addingTimeInterval(.hours(hours)) > now && $0.carbs > 0
            }
        }

        func announcement(_ hours: Int) async -> [Announcement] {
            let now = Date()
            return await announcementStorage.validate().filter {
                $0.createdAt.addingTimeInterval(.hours(hours)) > now
            }
        }
    }
}
