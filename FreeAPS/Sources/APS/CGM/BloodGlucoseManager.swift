import Foundation
import Swinject
import UIKit

final class BloodGlucoseManager: Sendable {
    private let glucoseStorage: GlucoseStorage

    init(resolver: Resolver) {
        glucoseStorage = resolver.resolve(GlucoseStorage.self)!
    }

    /// return true if a newer blood glucose record was detected and stored
    func storeNewBloodGlucose(
        bloodGlucose: [BloodGlucose],
        completion: @escaping @Sendable(Bool) -> Void
    ) {
        Task {
            // TODO: this used to be serialized in the process queue, but now the storage calls are async
            // investigate if this can be a problem
            let newBloodGlucoseStored = await self.glucoseStoreAndHeartDecision(
                glucose: bloodGlucose
            )
            completion(newBloodGlucoseStored)
        }
    }

    private func glucoseStoreAndHeartDecision(glucose: [BloodGlucose]) async -> Bool {
        guard glucose.isNotEmpty else { return false }

        // start background time extension
        let backgroundTaskIdBox = TaskIDBox()
        await MainActor.run {
            backgroundTaskIdBox.id = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdBox.id)
            }
        }

        let previousLatestBG = await glucoseStorage.latestDate()
        let storedGlucose = await glucoseStorage.storeGlucose(glucose)
        let updatedLatestBG = storedGlucose.first?.dateString

        var newGlucoseStored = false
        if let previousLatestBG, let updatedLatestBG {
            newGlucoseStored = updatedLatestBG > previousLatestBG
        } else {
            newGlucoseStored = previousLatestBG == nil && updatedLatestBG != nil
        }

        if newGlucoseStored {
            debug(.deviceManager, "New glucose found")
        }

        // end of the BG tasks
        await MainActor.run {
            if backgroundTaskIdBox.id != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdBox.id)
            }
        }

        return newGlucoseStored
    }
}
