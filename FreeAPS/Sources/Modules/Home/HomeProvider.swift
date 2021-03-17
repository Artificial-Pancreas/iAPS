import Foundation
import SwiftDate

extension Home {
    final class Provider: BaseProvider, HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!

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

        func pumpSettings() -> PumpSettings {
            (try? storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self))
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 5, maxBolus: 10, maxBasal: 2)
        }
    }
}
