import Combine
import Foundation

final class AppCoordinator {
    private let _heartbeat = PassthroughSubject<Void, Never>()

    @Published private(set) var shouldUploadGlucose: Bool = false
    @Published private(set) var sensorDays: Double? = nil

    let isLooping = CurrentValueSubject<Bool, Never>(false)

    var heartbeat: AnyPublisher<Void, Never> {
        _heartbeat.eraseToAnyPublisher()
    }

    func sendHeartbeat() {
        _heartbeat.send(())
    }

    func setShouldUploadGlucose(_ shouldUpload: Bool) {
        shouldUploadGlucose = shouldUpload
    }

    /// Called from every CGM state update (on the device manager's queue; the G7 mutates state on
    /// each reading) and from setupCGM on main. The compare-and-publish happens on main so the two
    /// callers cannot race and the @Published change reaches SwiftUI on the right thread; only a
    /// change is published.
    func setSensorDays(_ sensorDays: Double?) {
        DispatchQueue.main.async {
            guard self.sensorDays != sensorDays else { return }
            self.sensorDays = sensorDays
        }
    }
}
