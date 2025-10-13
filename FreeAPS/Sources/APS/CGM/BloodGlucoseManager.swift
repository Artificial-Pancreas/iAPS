import Combine
import Foundation
import Swinject
import UIKit

final class BloodGlucoseManager {
    private let processQueue = DispatchQueue(label: "BaseCGMPluginManager.processQueue")
    private let glucoseStorage: GlucoseStorage
    private let broadcaster: Broadcaster

    init(resolver: Resolver) {
        glucoseStorage = resolver.resolve(GlucoseStorage.self)!
        broadcaster = resolver.resolve(Broadcaster.self)!
    }

    /// return true if a newer blood glucose record was detected and stored
    func storeNewBloodGlucose(
        bloodGlucose: [BloodGlucose],
        completion: @escaping (Bool) -> Void
    ) {
        processQueue.async {
            let newBloodGlucoseStored = self.glucoseStoreAndHeartDecision(
                glucose: bloodGlucose
            )
            completion(newBloodGlucoseStored)
        }
    }

    private func glucoseStoreAndHeartDecision(glucose: [BloodGlucose]) -> Bool {
        guard glucose.isNotEmpty else { return false }

        // start background time extension
        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
            guard let bg = backGroundFetchBGTaskID else { return }
            UIApplication.shared.endBackgroundTask(bg)
            backGroundFetchBGTaskID = .invalid
        }

        let previousLatestBG = glucoseStorage.latestDate()
        let storedGlucose = glucoseStorage.storeGlucose(glucose)
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
        if let backgroundTask = backGroundFetchBGTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backGroundFetchBGTaskID = .invalid
        }

        return newGlucoseStored
    }
}
