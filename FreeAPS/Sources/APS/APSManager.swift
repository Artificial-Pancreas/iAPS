import Combine
import Foundation
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject

protocol APSManager {
    func heartbeat(date: Date, force: Bool)
    func autotune() -> AnyPublisher<Autotune?, Never>
    func enactBolus(amount: Double, isSMB: Bool)
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var isLooping: CurrentValueSubject<Bool, Never> { get }
    var lastLoopDate: Date { get }
    var lastLoopDateSubject: PassthroughSubject<Date, Never> { get }
    var bolusProgress: CurrentValueSubject<Decimal?, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    func enactTempBasal(rate: Double, duration: TimeInterval)
    func makeProfiles() -> AnyPublisher<Bool, Never>
    func determineBasal() -> AnyPublisher<Bool, Never>
    func determineBasalSync()
    func roundBolus(amount: Decimal) -> Decimal
    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus()
    func enactAnnouncement(_ announcement: Announcement)
}

enum APSError: LocalizedError {
    case pumpError(Error)
    case invalidPumpState(message: String)
    case glucoseError(message: String)
    case apsError(message: String)
    case deviceSyncError(message: String)

    var errorDescription: String? {
        switch self {
        case let .pumpError(error):
            return "Pump error: \(error.localizedDescription)"
        case let .invalidPumpState(message):
            return "Error: Invalid Pump State: \(message)"
        case let .glucoseError(message):
            return "Error: Invalid glucose: \(message)"
        case let .apsError(message):
            return "APS error: \(message)"
        case let .deviceSyncError(message):
            return "Sync error: \(message)"
        }
    }
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
    @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date()
    @Persisted(key: "lastLoopDate") var lastLoopDate: Date = .distantPast {
        didSet {
            lastLoopDateSubject.send(lastLoopDate)
        }
    }

    private var openAPS: OpenAPS!

    private var lifetime = Lifetime()

    var pumpManager: PumpManagerUI? {
        get { deviceDataManager.pumpManager }
        set { deviceDataManager.pumpManager = newValue }
    }

    let isLooping = CurrentValueSubject<Bool, Never>(false)
    let lastLoopDateSubject = PassthroughSubject<Date, Never>()
    let lastError = CurrentValueSubject<Error?, Never>(nil)

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> {
        deviceDataManager.pumpDisplayState
    }

    var pumpName: CurrentValueSubject<String, Never> {
        deviceDataManager.pumpName
    }

    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> {
        deviceDataManager.pumpExpiresAtDate
    }

    var settings: FreeAPSSettings {
        get { settingsManager.settings }
        set { settingsManager.settings = newValue }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: storage)
        subscribe()
        lastLoopDateSubject.send(lastLoopDate)
    }

    private func subscribe() {
        deviceDataManager.recommendsLoop
            .receive(on: processQueue)
            .sink { [weak self] in
                self?.loop()
            }
            .store(in: &lifetime)
        pumpManager?.addStatusObserver(self, queue: processQueue)

        deviceDataManager.errorSubject
            .receive(on: processQueue)
            .map { APSError.pumpError($0) }
            .sink {
                self.processError($0)
            }
            .store(in: &lifetime)

        deviceDataManager.bolusTrigger
            .receive(on: processQueue)
            .sink { bolusing in
                if bolusing {
                    self.createBolusReporter()
                } else {
                    self.clearBolusReporter()
                }
            }
            .store(in: &lifetime)
    }

    func heartbeat(date: Date, force: Bool) {
        deviceDataManager.heartbeat(date: date, force: force)
    }

    private func loop() {
        guard !isLooping.value else {
            warning(.apsManager, "Already looping, skip")
            return
        }

        debug(.apsManager, "Starting loop")
        isLooping.send(true)
        determineBasal()
            .sink { _ in } receiveValue: { [weak self] ok in
                guard let self = self else { return }

                if ok {
                    self.nightscout.uploadStatus()
                    if self.settings.closedLoop {
                        self.enactSuggested()
                    } else {
                        self.isLooping.send(false)
                        self.lastLoopDate = Date()
                    }
                } else {
                    self.isLooping.send(false)
                }
            }.store(in: &lifetime)
    }

    private func verifyStatus() -> Bool {
        guard let pump = pumpManager else {
            debug(.apsManager, "Pump is not set")
            processError(APSError.invalidPumpState(message: "Pump is not set"))
            return false
        }
        let status = pump.status.pumpStatus

        guard !status.bolusing else {
            debug(.apsManager, "Pump is bolusing")
            processError(APSError.invalidPumpState(message: "Pump is bolusing"))
            return false
        }

        guard !status.suspended else {
            debug(.apsManager, "Pump suspended")
            processError(APSError.invalidPumpState(message: "Pump suspended"))
            return false
        }

        let reservoir = storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self) ?? 100
        guard reservoir > 0 else {
            debug(.apsManager, "Reservoir is empty")
            processError(APSError.invalidPumpState(message: "Reservoir is empty"))
            return false
        }

        return true
    }

    private func autosens() -> AnyPublisher<Bool, Never> {
        guard let autosens = storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self),
              (autosens.timestamp ?? .distantPast).addingTimeInterval(30.minutes.timeInterval) > Date()
        else {
            return openAPS.autosense()
                .map { $0 != nil }
                .eraseToAnyPublisher()
        }

        return Just(false).eraseToAnyPublisher()
    }

    func determineBasal() -> AnyPublisher<Bool, Never> {
        debug(.apsManager, "Start determine basal")
        guard let glucose = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self), glucose.isNotEmpty else {
            debug(.apsManager, "Not enough glucose data")
            processError(APSError.glucoseError(message: "Not enough glucose data"))
            return Just(false).eraseToAnyPublisher()
        }

        let lastGlucoseDate = glucoseStorage.lastGlucoseDate()
        guard lastGlucoseDate >= Date().addingTimeInterval(-12.minutes.timeInterval) else {
            debug(.apsManager, "Glucose data is stale")
            processError(APSError.glucoseError(message: "Glucose data is stale"))
            return Just(false).eraseToAnyPublisher()
        }

        guard glucoseStorage.isGlucoseNotFlat() else {
            debug(.apsManager, "Glucose data is too flat")
            processError(APSError.glucoseError(message: "Glucose data is too flat"))
            return Just(false).eraseToAnyPublisher()
        }

        let now = Date()
        let temp = currentTemp(date: now)

        let mainPublisher = makeProfiles()
            .flatMap { _ in self.autosens() }
            .flatMap { _ in self.dailyAutotune() }
            .flatMap { _ in self.openAPS.determineBasal(currentTemp: temp, clock: now) }
            .map { suggestion -> Bool in
                if let suggestion = suggestion {
                    DispatchQueue.main.async {
                        self.broadcaster.notify(SuggestionObserver.self, on: .main) {
                            $0.suggestionDidUpdate(suggestion)
                        }
                    }
                }

                return suggestion != nil
            }
            .eraseToAnyPublisher()

        if temp.duration == 0,
           settings.closedLoop,
           settingsManager.preferences.unsuspendIfNoTemp,
           let pump = pumpManager,
           pump.status.pumpStatus.suspended
        {
            return pump.resumeDelivery()
                .flatMap { _ in mainPublisher }
                .replaceError(with: false)
                .eraseToAnyPublisher()
        }

        return mainPublisher
    }

    func determineBasalSync() {
        determineBasal().cancellable().store(in: &lifetime)
    }

    func makeProfiles() -> AnyPublisher<Bool, Never> {
        openAPS.makeProfiles(useAutotune: settings.useAutotune)
            .map { tunedProfile in
                if let basalProfile = tunedProfile?.basalProfile {
                    self.processQueue.async {
                        self.broadcaster.notify(BasalProfileObserver.self, on: self.processQueue) {
                            $0.basalProfileDidChange(basalProfile)
                        }
                    }
                }

                return tunedProfile != nil
            }
            .eraseToAnyPublisher()
    }

    func roundBolus(amount: Decimal) -> Decimal {
        guard let pump = pumpManager, verifyStatus() else { return amount }
        return Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
    }

    private var bolusReporter: DoseProgressReporter?

    func enactBolus(amount: Double, isSMB: Bool) {
        guard let pump = pumpManager, verifyStatus() else { return }

        let roundedAmout = pump.roundToSupportedBolusVolume(units: amount)

        debug(.apsManager, "Enact bolus \(roundedAmout), manual \(!isSMB)")

        pump.enactBolus(units: roundedAmout, automatic: isSMB).sink { completion in
            if case let .failure(error) = completion {
                warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            } else {
                debug(.apsManager, "Bolus succeeded")
                if !isSMB {
                    self.determineBasal().sink { _ in }.store(in: &self.lifetime)
                }
                self.bolusProgress.send(0)
            }
        } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func cancelBolus() {
        guard let pump = pumpManager, pump.status.pumpStatus.bolusing else { return }
        debug(.apsManager, "Cancel bolus")
        pump.cancelBolus().sink { completion in
            if case let .failure(error) = completion {
                debug(.apsManager, "Bolus cancellation failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            } else {
                debug(.apsManager, "Bolus cancelled")
            }

            self.bolusReporter?.removeObserver(self)
            self.bolusReporter = nil
            self.bolusProgress.send(nil)
        } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) {
        guard let pump = pumpManager, verifyStatus() else { return }
        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")

        let roundedAmout = pump.roundToSupportedBasalRate(unitsPerHour: rate)
        pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration) { result in
            switch result {
            case .success:
                debug(.apsManager, "Temp Basal succeeded")
                let temp = TempBasal(duration: Int(duration / 60), rate: Decimal(rate), temp: .absolute, timestamp: Date())
                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
            case let .failure(error):
                debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            }
        }
    }

    func dailyAutotune() -> AnyPublisher<Bool, Never> {
        guard settings.useAutotune else {
            return Just(false).eraseToAnyPublisher()
        }

        let now = Date()

        guard lastAutotuneDate.isBeforeDate(now, granularity: .day) else {
            return Just(false).eraseToAnyPublisher()
        }
        lastAutotuneDate = now

        return autotune().map { $0 != nil }.eraseToAnyPublisher()
    }

    func autotune() -> AnyPublisher<Autotune?, Never> {
        openAPS.autotune().eraseToAnyPublisher()
    }

    func enactAnnouncement(_ announcement: Announcement) {
        guard let action = announcement.action else {
            warning(.apsManager, "Invalid Announcement action")
            return
        }

        guard let pump = pumpManager else {
            warning(.apsManager, "Pump is not set")
            return
        }

        debug(.apsManager, "Start enact announcement: \(action)")

        switch action {
        case let .bolus(amount):
            guard verifyStatus() else {
                return
            }
            let roundedAmount = pump.roundToSupportedBolusVolume(units: Double(amount))
            pump.enactBolus(units: roundedAmount, automatic: false) { result in
                switch result {
                case .success:
                    debug(.apsManager, "Announcement Bolus succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    self.bolusProgress.send(0)
                case let .failure(error):
                    warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                }
            }
        case let .pump(pumpAction):
            switch pumpAction {
            case .suspend:
                guard verifyStatus(), !pump.status.pumpStatus.suspended else {
                    return
                }
                pump.suspendDelivery { error in
                    if let error = error {
                        debug(.apsManager, "Pump not suspended by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump suspended by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            case .resume:
                guard pump.status.pumpStatus.suspended else {
                    return
                }
                pump.resumeDelivery { error in
                    if let error = error {
                        warning(.apsManager, "Pump not resumed by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump resumed by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            }
        case let .looping(closedLoop):
            settings.closedLoop = closedLoop
            debug(.apsManager, "Closed loop \(closedLoop) by Announcement")
            announcementsStorage.storeAnnouncements([announcement], enacted: true)
        case let .tempbasal(rate, duration):
            guard verifyStatus(), !settings.closedLoop else {
                return
            }
            let roundedRate = pump.roundToSupportedBasalRate(unitsPerHour: Double(rate))
            pump.enactTempBasal(unitsPerHour: roundedRate, for: TimeInterval(duration) * 60) { result in
                switch result {
                case .success:
                    debug(.apsManager, "Announcement TempBasal succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                case let .failure(error):
                    warning(.apsManager, "Announcement TempBasal failed with error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func currentTemp(date: Date) -> TempBasal {
        let defaultTemp = { () -> TempBasal in
            guard let temp = storage.retrieve(OpenAPS.Monitor.tempBasal, as: TempBasal.self) else {
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
        guard let suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) else {
            isLooping.send(false)
            warning(.apsManager, "Suggestion not found")
            processError(APSError.apsError(message: "Suggestion not found"))
            return
        }

        guard Date().timeIntervalSince(suggested.deliverAt ?? .distantPast) < Config.eхpirationInterval else {
            isLooping.send(false)
            warning(.apsManager, "Suggestion expired")
            processError(APSError.apsError(message: "Suggestion expired"))
            return
        }

        guard let pump = pumpManager, verifyStatus() else {
            isLooping.send(false)
            warning(.apsManager, "Invalid pump state")
            return
        }

        let basalPublisher: AnyPublisher<Void, Error> = {
            guard let rate = suggested.rate, let duration = suggested.duration else {
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactTempBasal(unitsPerHour: Double(rate), for: TimeInterval(duration * 60)).map { _ in
                let temp = TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: Date())
                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                return ()
            }
            .eraseToAnyPublisher()
        }()

        let bolusPublisher: AnyPublisher<Void, Error> = {
            guard let units = suggested.units else {
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactBolus(units: Double(units), automatic: true).map { _ in
                self.bolusProgress.send(0)
                return ()
            }
            .eraseToAnyPublisher()
        }()

        basalPublisher
            .flatMap { bolusPublisher }
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
                    self?.reportEnacted(suggestion: suggested, received: false)
                    self?.processError(APSError.pumpError(error))
                } else {
                    self?.reportEnacted(suggestion: suggested, received: true)
                }
                self?.isLooping.send(false)
            } receiveValue: {
                debug(.apsManager, "Loop succeeded")
                self.lastError.send(nil)
                self.lastLoopDate = Date()
            }.store(in: &lifetime)
    }

    private func reportEnacted(suggestion: Suggestion, received: Bool) {
        if suggestion.deliverAt != nil {
            var enacted = suggestion
            enacted.timestamp = Date()
            enacted.recieved = received
            storage.save(enacted, as: OpenAPS.Enact.enacted)
            debug(.apsManager, "Suggestion enacted")
            DispatchQueue.main.async {
                self.broadcaster.notify(EnactedSuggestionObserver.self, on: .main) {
                    $0.enactedSuggestionDidUpdate(enacted)
                }
            }
            nightscout.uploadStatus()
        }
    }

    private func processError(_ error: Error) {
        warning(.apsManager, "\(error.localizedDescription)")
        lastError.send(error)
    }

    private func createBolusReporter() {
        bolusReporter = pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
        bolusReporter?.addObserver(self)
    }

    private func clearBolusReporter() {
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        processQueue.asyncAfter(deadline: .now() + 1) {
            self.bolusProgress.send(nil)
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

    func cancelBolus() -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            self.cancelBolus { result in
                switch result {
                case let .success(dose):
                    promise(.success(dose))
                case let .failure(error):
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
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
        let percent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: percent,
            voltage: nil,
            string: percent > 10 ? .normal : .low,
            display: status.pumpBatteryChargeRemaining != nil
        )
        storage.save(battery, as: OpenAPS.Monitor.battery)
        storage.save(status.pumpStatus, as: OpenAPS.Monitor.status)
    }
}

extension BaseAPSManager: DoseProgressObserver {
    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {
        bolusProgress.send(Decimal(doseProgressReporter.progress.percentComplete))
        if doseProgressReporter.progress.isComplete {
            clearBolusReporter()
        }
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
