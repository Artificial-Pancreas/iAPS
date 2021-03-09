import Combine
import Foundation
import LoopKit
import LoopKitUI
import Swinject

protocol APSManager {
    func fetchAndLoop()
    func autosense()
    func autotune()
    func enactBolus(amount: Double)
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    func enactTempBasal(rate: Double, duration: TimeInterval)
}

final class BaseAPSManager: APSManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseAPSManager.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var nightscout: NightscoutManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    private var openAPS: OpenAPS!

    private var lifetime = Set<AnyCancellable>()

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
        deviceDataManager.recommendsLoop
            .sink { [weak self] in
                self?.fetchAndLoop()
            }
            .store(in: &lifetime)
        pumpManager?.addStatusObserver(self, queue: processQueue)
    }

    func fetchAndLoop() {
        guard pumpManager != nil else {
            loop()
            return
        }

        nightscout.fetchAnnouncements()
            .sink { [weak self] in
                if let recent = self?.announcementsStorage.recent(), recent.action != nil {
                    self?.enactAnnouncement(recent)
                } else {
                    self?.loop()
                }
            }.store(in: &lifetime)
    }

    private func loop() {
        Publishers.CombineLatest3(
            nightscout.fetchGlucose(),
            nightscout.fetchCarbs(),
            nightscout.fetchTempTargets()
        )
        .flatMap { _ in self.determineBasal() }
        .sink { _ in } receiveValue: { [weak self] ok in
            guard let self = self else { return }
            if ok, let suggested = try? self.storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) {
                DispatchQueue.main.async {
                    self.broadcaster.notify(SuggestionObserver.self, on: .main) {
                        $0.suggestionDidUpdate(suggested)
                    }
                }
                self.nightscout.uploadStatus()
            }

            if ok, self.settings.closedLoop {
                self.enactSuggested()
            }
        }.store(in: &lifetime)
    }

    private func verifyStatus() -> Bool {
        guard let pump = pumpManager else {
            return false
        }
        let status = pump.status.pumpStatus

        guard !status.bolusing, !status.suspended else { return false }

        return true
    }

    private func determineBasal() -> AnyPublisher<Bool, Never> {
        guard let glucose = try? storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self), glucose.count >= 36 else {
            debug(.apsManager, "Not enough glucose data")
            return Just(false).eraseToAnyPublisher()
        }

        let now = Date()
        let temp = currentTemp(date: now)

        let mainPublisher = openAPS.makeProfiles()
            .flatMap { _ in
                self.openAPS.determineBasal(currentTemp: temp, clock: now)
            }
            .map { true }
            .eraseToAnyPublisher()

        if temp.duration == 0,
           settings.closedLoop,
           settingsManager.preferences.unsuspendIfNoTemp,
           let pump = pumpManager
        {
            return pump.resumeDelivery()
                .flatMap { _ in mainPublisher }
                .replaceError(with: false)
                .eraseToAnyPublisher()
        }

        return mainPublisher
    }

    func enactBolus(amount: Double) {
        guard let pump = pumpManager, verifyStatus() else { return }

        let roundedAmout = pump.roundToSupportedBolusVolume(units: amount)
        pump.enactBolus(units: roundedAmout, automatic: false) { result in
            switch result {
            case .success:
                debug(.apsManager, "Bolus succeeded")
            case let .failure(error):
                debug(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
            }
        }
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) {
        guard let pump = pumpManager, verifyStatus() else { return }

        let roundedAmout = pump.roundToSupportedBasalRate(unitsPerHour: rate)
        pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration) { result in
            switch result {
            case .success:
                debug(.apsManager, "Temp Basal succeeded")
                let temp = TempBasal(duration: Int(duration / 60), rate: Decimal(rate), temp: .absolute, timestamp: Date())
                try? self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
            case let .failure(error):
                debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
            }
        }
    }

    func autosense() {
        openAPS.autosense().sink {}.store(in: &lifetime)
    }

    func autotune() {
        openAPS.autotune().sink {}.store(in: &lifetime)
    }

    private func enactAnnouncement(_ announcement: Announcement) {
        guard let action = announcement.action else {
            debug(.apsManager, "Invalid Announcement action")
            return
        }
        switch action {
        case let .bolus(amount):
            guard verifyStatus() else {
                return
            }
            pumpManager?.enactBolus(units: Double(amount), automatic: false) { result in
                switch result {
                case .success:
                    debug(.apsManager, "Announcement Bolus succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                case let .failure(error):
                    debug(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                }
            }
        case let .pump(pumpAction):
            switch pumpAction {
            case .suspend:
                guard verifyStatus() else {
                    return
                }
                pumpManager?.suspendDelivery { error in
                    if let error = error {
                        debug(.apsManager, "Pump not suspended by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump suspended by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    }
                }
            case .resume:
                pumpManager?.resumeDelivery { error in
                    if let error = error {
                        debug(.apsManager, "Pump not resumed by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump resumed by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    }
                }
            }
        case let .looping(closedLoop):
            settings.closedLoop = closedLoop
            debug(.apsManager, "Closed loop \(closedLoop) by Announcement")
            announcementsStorage.storeAnnouncements([announcement], enacted: true)
        case let .tempbasal(rate, duration):
            guard verifyStatus() else {
                return
            }
            pumpManager?.enactTempBasal(unitsPerHour: Double(rate), for: TimeInterval(duration) * 60) { result in
                switch result {
                case .success:
                    debug(.apsManager, "Announcement TempBasal succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                case let .failure(error):
                    debug(.apsManager, "Announcement TempBasal failed with error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func currentTemp(date: Date) -> TempBasal {
        let defaultTemp = { () -> TempBasal in
            guard let temp = try? storage.retrieve(OpenAPS.Monitor.tempBasal, as: TempBasal.self) else {
                return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
            }
            let delta = Int((date.timeIntervalSince1970 - temp.timestamp.timeIntervalSince1970) / 60)
            let duration = max(0, temp.duration - delta)
            return TempBasal(duration: duration, rate: temp.rate, temp: .absolute, timestamp: date)
        }()

        guard let state = pumpManager?.status.basalDeliveryState else { return defaultTemp }
        switch state {
        case .active:
            return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: date)
        case let .tempBasal(dose):
            let rate = Decimal(dose.unitsPerHour)
            let durationMin = max(0, Int((dose.endDate.timeIntervalSince1970 - date.timeIntervalSince1970) / 60))
            return TempBasal(duration: durationMin, rate: rate, temp: .absolute, timestamp: date)
        default:
            return defaultTemp
        }
    }

    private func enactSuggested() {
        guard verifyStatus() else {
            return
        }

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
            return pump.enactTempBasal(unitsPerHour: Double(rate), for: TimeInterval(duration * 60)).map { _ in
                let temp = TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: Date())
                try? self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                return ()
            }
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

        basalPublisher
            .flatMap { bolusPublisher }
            .sink { completion in
                if case let .failure(error) = completion {
                    debug(.apsManager, "Loop failed with error: \(error.localizedDescription)")
                }
            } receiveValue: { [weak self] in
                debug(.apsManager, "Loop succeeded")
                var enacted = suggested
                enacted.timestamp = Date()
                enacted.recieved = true
                try? self?.storage.save(enacted, as: OpenAPS.Enact.enacted)
                self?.nightscout.uploadStatus()
            }.store(in: &lifetime)
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

    func suspendDelivery() -> AnyPublisher<Void, Error> {
        Future { promise in
            self.suspendDelivery { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }

    func resumeDelivery() -> AnyPublisher<Void, Error> {
        Future { promise in
            self.resumeDelivery { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }
}

extension BaseAPSManager: PumpManagerStatusObserver {
    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        try? storage.save(status.pumpStatus, as: OpenAPS.Monitor.status)
        let percent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(percent: percent, voltage: nil, string: percent > 10 ? .normal : .low)
        try? storage.save(battery, as: OpenAPS.Monitor.battery)
    }
}

extension PumpManagerStatus {
    var pumpStatus: PumpStatus {
        let bolusing = bolusState != .noBolus
        let suspended = basalDeliveryState?.isSuspended ?? true
        let type = suspended ? StatusType.suspended : (bolusing ? .bolusing : .normal)
        return PumpStatus(status: type, bolusing: bolusing, suspended: suspended, timestamp: Date())
    }
}
