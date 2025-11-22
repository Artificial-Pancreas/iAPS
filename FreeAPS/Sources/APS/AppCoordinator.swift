import Combine
import Foundation

final class AppCoordinator {
    private let _heartbeat = PassthroughSubject<Void, Never>()

    @Published private(set) var shouldUploadGlucose: Bool = false
    @Published private(set) var sensorDays: Double? = nil

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
        self.sensorDays = sensorDays
    }
}
