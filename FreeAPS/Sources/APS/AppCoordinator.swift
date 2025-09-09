import Combine
import Foundation

final class AppCoordinator {
    private let _heartbeat = PassthroughSubject<Date, Never>()
    private let _bloodGlucose = PassthroughSubject<[BloodGlucose], Never>()
    private let _recommendsLoop = PassthroughSubject<Void, Never>()

    @Published private(set) var shouldUploadGlucose: Bool = false

    var heartbeat: AnyPublisher<Date, Never> {
        _heartbeat.eraseToAnyPublisher()
    }

    var bloodGlucose: AnyPublisher<[BloodGlucose], Never> {
        _bloodGlucose.eraseToAnyPublisher()
    }

    var recommendsLoop: AnyPublisher<Void, Never> {
        _recommendsLoop.eraseToAnyPublisher()
    }

    func sendHeartbeat(date: Date) {
        _heartbeat.send(date)
    }

    func sendBloodGlucose(bloodGlucose: [BloodGlucose]) {
        _bloodGlucose.send(bloodGlucose)
    }

    func sendRecommendsLoop() {
        _recommendsLoop.send(())
    }

    func setShouldUploadGlucose(_ shouldUpload: Bool) {
        print("shouldUploadGlucose: \(shouldUpload)")
        shouldUploadGlucose = shouldUpload
    }
}
