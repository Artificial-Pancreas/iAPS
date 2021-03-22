import Foundation
import SwiftDate

extension Home {
    final class Provider: BaseProvider, HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() var carbsStorage: CarbsStorage!

        var suggestion: Suggestion? {
            try? storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }

        func fetchAndLoop() {
            apsManager.fetchAndLoop()
        }

        func filteredGlucose(hours: Int) -> [BloodGlucose] {
            glucoseStorage.recent().filter {
                $0.dateString.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func pumpHistory(hours: Int) -> [PumpHistoryEvent] {
            pumpHistoryStorage.recent().filter {
                $0.timestamp.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func tempTargets(hours: Int) -> [TempTarget] {
            tempTargetsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func carbs(hours: Int) -> [CarbsEntry] {
            carbsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func pumpSettings() -> PumpSettings {
            (try? storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self))
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 5, maxBolus: 10, maxBasal: 2)
        }

        func basalProfile() -> [BasalProfileEntry] {
            (try? storage.retrieve(OpenAPS.Settings.profile, as: Autotune.self))?.basalProfile
                ?? (try? storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self))?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }
    }
}
