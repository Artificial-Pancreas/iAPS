import Foundation
import SwiftDate

extension Home {
    final class Provider: BaseProvider, HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var glucoseStorage: GlucoseStorage!

        var suggestion: Suggestion? {
            try? storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }

        func fetchAndLoop() {
            apsManager.fetchAndLoop()
        }

        func filteredGlucose() -> [BloodGlucose] {
            glucoseStorage.recent().filter {
                $0.dateString.addingTimeInterval(3.hours.timeInterval) > Date()
            }
        }
    }
}
