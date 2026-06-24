import Foundation
import Swinject
import UIKit

final class BloodGlucoseManager: Sendable {
    private let glucoseStorage: GlucoseStorage

    private let serializer = TaskSerializer()

    init(resolver: Resolver) {
        glucoseStorage = resolver.resolve(GlucoseStorage.self)!
    }

    /// return true if a newer blood glucose record was detected and stored
    func storeNewBloodGlucose(
        bloodGlucose glucose: [BloodGlucose],
    ) async -> Bool {
        await serializer.run {
            guard glucose.isNotEmpty else { return false }

            let previousLatestBG = await glucoseStorage.latestDate()

            // glucoseStorage.storeGlucose returns nil when no new records were recorded (empty or duplicates)
            // TODO: this call can also return previousLatestBG, so we update and get all data "atomically"
            guard let storedGlucose = await glucoseStorage.storeGlucose(glucose) else {
                return false
            }
            let updatedLatestBG = storedGlucose.first?.dateString

            var newGlucoseStored = false
            if let previousLatestBG, let updatedLatestBG {
                newGlucoseStored = updatedLatestBG > previousLatestBG
            } else {
                newGlucoseStored = previousLatestBG == nil && updatedLatestBG != nil
            }

            if newGlucoseStored {
                debug(.deviceManager, "new glucose records stored")
            }

            return newGlucoseStored
        }
    }
}
