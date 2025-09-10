import Combine
import Foundation

final class AppCoordinator {
    private let _heartbeat = PassthroughSubject<Date, Never>()

    @Published private(set) var shouldUploadGlucose: Bool = false

    var heartbeat: AnyPublisher<Date, Never> {
        _heartbeat.eraseToAnyPublisher()
    }

    func sendHeartbeat(date: Date) {
        _heartbeat.send(date)
    }

    func setShouldUploadGlucose(_ shouldUpload: Bool) {
        shouldUploadGlucose = shouldUpload
    }
}
