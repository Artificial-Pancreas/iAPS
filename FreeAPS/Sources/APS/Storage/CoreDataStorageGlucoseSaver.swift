import Foundation
import Swinject

final class CoreDataStorageGlucoseSaver: NewGlucoseObserver {
    private let broadcaster: Broadcaster!

    init(resolver: Resolver) {
        broadcaster = resolver.resolve(Broadcaster.self)!
        subscribe()
    }

    private func subscribe() {
        broadcaster.register(NewGlucoseObserver.self, observer: self)
    }

    func newGlucoseStored(_ bloodGlucose: [BloodGlucose]) {
        CoreDataStorage().saveGlucoseInBackground(bloodGlucose: bloodGlucose)
    }
}
