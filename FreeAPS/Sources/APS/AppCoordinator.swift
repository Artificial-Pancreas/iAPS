import Combine
import Foundation

final class AppCoordinator {
    private let _heartbeat = PassthroughSubject<Void, Never>()

    @Published private(set) var shouldUploadGlucose: Bool = false

    var heartbeat: AnyPublisher<Void, Never> {
        _heartbeat.eraseToAnyPublisher()
    }

    func sendHeartbeat() {
        _heartbeat.send(())
    }

    func setShouldUploadGlucose(_ shouldUpload: Bool) {
        shouldUploadGlucose = shouldUpload
    }
}
