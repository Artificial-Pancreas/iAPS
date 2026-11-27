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
        private let statistics: GlucoseStatistics
        private let insulinStatistics: InsulinStatsService
        private let loops: HomeLoopsStore

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
            statistics = resolver.resolve(GlucoseStatistics.self)!
            insulinStatistics = resolver.resolve(InsulinStatsService.self)!
            loops = resolver.resolve(HomeLoopsStore.self)!
        }

        func glucoseSummary(_ period: StatsPeriod, bands: StatsBands) async -> GlucoseSummary {
            await statistics.summary(period, bands: bands)
        }

        /// The Loops card's numbers for the range, up to now: read and computed off the main actor (the shared store, the
        /// Loops screen's and the Statistics Loop tab's too). nil when something couldn't be read.
        func loopStats(_ period: StatsPeriod, allowOneMinuteLoop: Bool) async -> HomeLoopStats? {
            await loops.stats(period, allowOneMinuteLoop: allowOneMinuteLoop, now: Date(), calendar: .current)
        }

        /// The meal card, Today, as of now: the meals of the Meals tab's Today read (the last 90 days, for the nutrient
        /// data rule, to the end of today), formatted here, off the main actor. No cache: a few rows a day. nil when the
        /// meals couldn't be read.
        func mealsCard() async -> HomeMealsCard.Content? {
            let calendar = Calendar.current
            let now = Date()
            let range = Stat.Provider.mealsRange(.today, now: now, calendar: calendar)
            do {
                let points = try await coreDateStorage.fetchMealPoints(from: range.start, to: range.end)
                return HomeMealsCard.Content(points: points, now: now, calendar: calendar)
            } catch {
                debug(.service, "Home meal card: reading the meals failed: \(error)")
                return nil
            }
        }

        /// The insulin card, Today: the 7 days before today and today (`InsulinStatsService.days(last:)`, from its day
        /// cache: after a loop only today is read), formatted here, off the main actor, as of the read's time (each
        /// day's insulin by it, the usual by it), taken before the read as the Insulin tab's (`Stat.Provider.insulin`:
        /// the service reads today up to its own clock, a moment later). nil when the insulin data couldn't be read.
        func insulinCard() async -> HomeInsulinCard.Content? {
            let now = Date()
            do {
                let days = try await insulinStatistics.days(last: HomeInsulinCard.Content.pastDays + 1)
                return HomeInsulinCard.Content(days: days, now: now, calendar: .current)
            } catch {
                debug(.service, "Home insulin card: reading the insulin data failed: \(error)")
                return nil
            }
        }

        func overrideHistory() async -> [OverrideHistorySnapshot] {
            await overrideStorage.fetchOverrideHistory(interval: DateFilter.day.startDate)
        }

        /// The loop's IOB and COB rows after `start`, newest -> oldest (the main chart's COB and the On board card,
        /// `Home.StateModel.setupData`)
        func reasons(since start: Date) async -> [IOBData] {
            let reasons = await coreDateStorage.fetchReasons(interval: start as NSDate)

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
