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

        let overrideStorage = OverrideStorage()
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
        }

        var dynamicVariables: DynamicVariables? {
            get async {
                await storage.retrieve(OpenAPS.Monitor.dynamicVariables, as: DynamicVariables.self)
            }
        }

        func fetchedMeals(_ interval: NSDate) async -> [MealsSnapshot] {
            await coreDateStorage.fetchMealData(
                interval: interval
            )
        }

        func overrides() async -> [OverrideSnapshot] {
            await overrideStorage.fetchOverrides(interval: DateFilter.day.startDate)
        }

        func latestOverride() async -> OverrideSnapshot? {
            await overrideStorage.fetchLatestOverride().first
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

        func filteredGlucose(hours: Int) async -> [BloodGlucose] {
            let now = Date()
            // .retrieve() will read glucose from storage and apply smoothing if needed
            return await glucoseStorage.retrieve().filter {
                $0.dateString.addingTimeInterval(hours.hours.timeInterval) > now
            }
        }

        func manualGlucose(hours: Int) async -> [BloodGlucose] {
            let now = Date()
            return await glucoseStorage.retrieve().filter {
                $0.type == GlucoseType.manual.rawValue &&
                    $0.dateString.addingTimeInterval(hours.hours.timeInterval) > now
            }
        }

        func pumpHistory(hours: Int) async -> [PumpHistoryEvent] {
            let now = Date()
            return appCoordinator.pumpHistory.value.filter {
                $0.timestamp.addingTimeInterval(hours.hours.timeInterval) > now
            }
        }

        func tempTargets(hours: Int) async -> [TempTarget] {
            let now = Date()
            return await tempTargetsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > now
            }
        }

        func tempTarget() async -> TempTarget? {
            await tempTargetsStorage.current()
        }

        func carbs(hours: Int) async -> [CarbsEntry] {
            let now = Date()
            return await carbsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > now && $0.carbs > 0
            }
        }

        func announcement(_ hours: Int) async -> [Announcement] {
            let now = Date()
            return await announcementStorage.validate().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > now
            }
        }

        func autotunedBasalProfile() async -> [BasalProfileEntry] {
            if let profile = await storage.retrieve(OpenAPS.Settings.profile, as: Autotune.self)?.basalProfile {
                return profile
            }
            if let profile = await storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile {
                return profile
            }
            return [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }

        func basalProfile() async -> [BasalProfileEntry] {
            await storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }
    }
}
