import Combine
import Foundation
import LoopKit
import LoopKitUI
import Swinject

protocol APSManager {
    func loop()
    func autosense()
    func autotune()
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
}

final class BaseAPSManager: APSManager, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var networkManager: NetworkManager!
    @Injected() private var settingsManager: SettingsManager!
    private var openAPS: OpenAPS!

    private var loopCancellable: AnyCancellable?
    private var pumpCancellable: AnyCancellable?
    private var enactCancellable: AnyCancellable?

    var pumpManager: PumpManagerUI? {
        get { deviceDataManager.pumpManager }
        set { deviceDataManager.pumpManager = newValue }
    }

    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> {
        deviceDataManager.pumpDisplayState
    }

    var settings: FreeAPSSettings {
        get { settingsManager.settings }
        set { settingsManager.settings = newValue }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: storage)
        subscribe()
    }

    private func subscribe() {
        pumpCancellable = deviceDataManager.recommendsLoop
            .sink { [weak self] in
                self?.loop()
            }
    }

    func loop() {
        loopCancellable = networkManager
            .fetchGlucose()
            .flatMap { [weak self] glucose -> AnyPublisher<Bool, Never> in
                guard let self = self else { return Just(false).eraseToAnyPublisher() }
                self.glucoseStorage.storeGlucose(glucose)
                return self.determineBasal()
            }
            .sink { _ in } receiveValue: { [weak self] ok in
                guard let self = self else { return }
                if ok, self.settings.closedLoop {
                    self.enactSuggested()
                }
            }
    }

    func determineBasal() -> AnyPublisher<Bool, Never> {
        guard let glucose = try? storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self), glucose.count >= 36 else {
            print("Not enough glucose data")
            return Just(false).eraseToAnyPublisher()
        }

        let now = Date()
        guard let temp = currentTemp(date: now) else {
            return Just(false).eraseToAnyPublisher()
        }

        return openAPS.makeProfiles()
            .flatMap { _ in
                self.openAPS.determineBasal(currentTemp: temp, clock: now)
            }
            .map { true }
            .eraseToAnyPublisher()
    }

    func autosense() {
        _ = openAPS.autosense()
    }

    func autotune() {
        _ = openAPS.autotune()
    }

    private func currentTemp(date: Date) -> TempBasal? {
        guard let state = pumpManager?.status.basalDeliveryState else { return nil }
        switch state {
        case .active:
            return TempBasal(duration: 0, rate: 0, temp: .absolute)
        case let .tempBasal(dose):
            let rate = Decimal(dose.unitsPerHour)
            let durationMin = max(0, Int((dose.endDate.timeIntervalSince1970 - date.timeIntervalSince1970) / 60))
            return TempBasal(duration: durationMin, rate: rate, temp: .absolute)
        default: return nil
        }
    }

    private func enactSuggested() {
        guard let pump = pumpManager,
              let suggested = try? storage.retrieve(
                  OpenAPS.Enact.suggested,
                  as: Suggestion.self
              )
        else {
            return
        }

        let basalPublisher: AnyPublisher<Void, Error> = {
            guard let rate = suggested.rate, let duration = suggested.duration else {
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactTempBasal(unitsPerHour: Double(rate), for: TimeInterval(duration * 60)).map { _ in () }
                .eraseToAnyPublisher()
        }()

        let bolusPublisher: AnyPublisher<Void, Error> = {
            guard let units = suggested.units else {
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactBolus(units: Double(units), automatic: true).map { _ in () }
                .eraseToAnyPublisher()
        }()

        enactCancellable = basalPublisher
            .flatMap { bolusPublisher }
            .sink { completion in
                if case let .failure(error) = completion {
                    print("Loop failed with error: \(error.localizedDescription)")
                }
            } receiveValue: { [weak self] in
                print("Loop succeeded")
                if let rawSuggested = self?.storage.retrieveRaw(OpenAPS.Enact.suggested) {
                    try? self?.storage.save(rawSuggested, as: OpenAPS.Enact.enacted)
                }
            }
    }
}

private extension PumpManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) -> AnyPublisher<DoseEntry, Error> {
        Future { promise in
            self.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { result in
                switch result {
                case let .success(dose):
                    promise(.success(dose))
                case let .failure(error):
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }

    func enactBolus(units: Double, automatic: Bool) -> AnyPublisher<DoseEntry, Error> {
        Future { promise in
            self.enactBolus(units: units, automatic: automatic) { result in
                switch result {
                case let .success(dose):
                    promise(.success(dose))
                case let .failure(error):
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
}
