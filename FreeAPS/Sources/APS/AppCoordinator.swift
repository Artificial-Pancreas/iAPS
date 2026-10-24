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

    func setSensorDays(_ sensorDays: Double?) {
        // Called from every CGM state update (G7 mutates state on each reading); only a change is worth publishing.
        guard self.sensorDays != sensorDays else { return }
        self.sensorDays = sensorDays
    }
}
