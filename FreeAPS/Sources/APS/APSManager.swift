import Combine
import Foundation
import LoopKit
import LoopKitUI
import Swinject

protocol APSManager {
    func determineBasal()
    func runTest()
    func makeProfiles()
    func fetchLastGlucose()
    func autosense()
    func autotune()
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
}

final class BaseAPSManager: APSManager, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var keychain: Keychain!
    @Injected() private var deviceDataManager: DeviceDataManager!
    private var openAPS: OpenAPS!

    private var glucoseCancellable: AnyCancellable?
    private var determineBasalCancellable: AnyCancellable?
    private var enactCancellable: AnyCancellable?

    var pumpManager: PumpManagerUI? {
        get {
            deviceDataManager.pumpManager
        }
        set {
            deviceDataManager.pumpManager = newValue
        }
    }

    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { deviceDataManager.pumpDisplayState }

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: storage)
    }

    func loop() {
        glucoseCancellable = fetchLastGlucose()
    }

    func determineBasal() {
        let now = Date()
        guard let temp = currentTemp(date: now) else {
            return
        }
        determineBasalCancellable = openAPS
            .determineBasal(currentTemp: temp, clock: now)
            .sink { [weak self] in
                guard let self = self,
                      let suggested = try? self.storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
                else {
                    return
                }
                self.enact(suggested: suggested)
            }
    }

    func runTest() {
        openAPS.test()
    }

    func makeProfiles() {
        openAPS.makeProfile(autotuned: false)
        openAPS.makeProfile(autotuned: true)
    }

    func fetchLastGlucose() {
        if let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
           let url = URL(string: urlString)
        {
            glucoseCancellable = NightscoutAPI(url: url).fetchLast(288)
                .sink { _ in }
            receiveValue: { glucose in
                self.glucoseStorage.storeGlucose(glucose)
            }
        }
    }

    func autosense() {
        openAPS.autosense()
    }

    func autotune() {
        openAPS.autotune()
    }

    private func currentTemp(date: Date) -> TempBasal? {
        guard let state = pumpManager?.status.basalDeliveryState else { return nil }
        guard let lastTemp = try? storage.retrieve(OpenAPS.Monitor.tempBasal, as: TempBasal.self) else {
            return TempBasal(duration: 0, rate: 0, temp: .absolute, updatedAt: date)
        }

        switch state {
        case .active:
            return TempBasal(duration: 0, rate: 0, temp: .absolute, updatedAt: date)
        case let .tempBasal(dose):
            let doseRate = Decimal(dose.unitsPerHour)
            if doseRate == lastTemp.rate {
                let durationMin = Int((date.timeIntervalSince1970 - lastTemp.updatedAt.timeIntervalSince1970) / 60)
                return TempBasal(duration: durationMin, rate: lastTemp.rate, temp: .absolute, updatedAt: date)
            } else {
                let durationMin = Int((date.timeIntervalSince1970 - dose.startDate.timeIntervalSince1970) / 60)
                return TempBasal(duration: durationMin, rate: doseRate, temp: .absolute, updatedAt: date)
            }
        default: return nil
        }
    }

    private func enact(suggested: Suggestion) {
        guard let pump = pumpManager else { return }

        enactCancellable = pump.enactTempBasal(
            unitsPerHour: Double(truncating: suggested.rate as NSNumber),
            for: TimeInterval(suggested.duration * 60)
        )
        .flatMap { dose -> AnyPublisher<DoseEntry, Error> in
            let units = suggested.units.map { Double(truncating: $0 as NSNumber) } ?? 0
            guard units > 0 else { return Just(dose).setFailureType(to: Error.self).eraseToAnyPublisher() }
            return pump.enactBolus(units: units, automatic: true)
        }
        .sink { completion in
            if case let .failure(error) = completion {
                print("Loop failed with error: \(error.localizedDescription)")
            }
        } receiveValue: { _ in
            print("Loop failed succeses")
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
