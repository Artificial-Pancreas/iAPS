import Combine
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import OmniBLE
import OmniKit
import RileyLinkKit
import SwiftDate
import Swinject

protocol APSManager {
    func heartbeat(date: Date)
    func autotune() -> AnyPublisher<Autotune?, Never>
    func enactBolus(amount: Double, isSMB: Bool)
    var pumpManager: PumpManagerUI? { get set }
    var bluetoothManager: BluetoothStateManager? { get }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var isLooping: CurrentValueSubject<Bool, Never> { get }
    var lastLoopDate: Date { get }
    var lastLoopDateSubject: PassthroughSubject<Date, Never> { get }
    var bolusProgress: CurrentValueSubject<Decimal?, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    var isManualTempBasal: Bool { get }
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
    case manualBasalTemp(message: String)

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
        case let .manualBasalTemp(message):
            return "Manual Basal Temp : \(message)"
        }
    }
}

final class BaseAPSManager: APSManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseAPSManager.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var alertHistoryStorage: AlertHistoryStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var nightscout: NightscoutManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var healthKitManager: HealthKitManager!
    @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date()
    @Persisted(key: "lastStartLoopDate") private var lastStartLoopDate: Date = .distantPast
    @Persisted(key: "lastLoopDate") var lastLoopDate: Date = .distantPast {
        didSet {
            lastLoopDateSubject.send(lastLoopDate)
        }
    }

    let coredataContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()

    private var openAPS: OpenAPS!

    private var lifetime = Lifetime()

    private var backGroundTaskID: UIBackgroundTaskIdentifier?

    var pumpManager: PumpManagerUI? {
        get { deviceDataManager.pumpManager }
        set { deviceDataManager.pumpManager = newValue }
    }

    var bluetoothManager: BluetoothStateManager? { deviceDataManager.bluetoothManager }

    @Persisted(key: "isManualTempBasal") var isManualTempBasal: Bool = false

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

        isLooping
            .weakAssign(to: \.deviceDataManager.loopInProgress, on: self)
            .store(in: &lifetime)
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

        // manage a manual Temp Basal from OmniPod - Force loop() after stop a temp basal or finished
        deviceDataManager.manualTempBasal
            .receive(on: processQueue)
            .sink { manualBasal in
                if manualBasal {
                    self.isManualTempBasal = true
                } else {
                    if self.isManualTempBasal {
                        self.isManualTempBasal = false
                        self.loop()
                    }
                }
            }
            .store(in: &lifetime)
    }

    func heartbeat(date: Date) {
        deviceDataManager.heartbeat(date: date)
    }

    // Loop entry point
    private func loop() {
        // check the last start of looping is more the loopInterval but the previous loop was completed
        if lastLoopDate > lastStartLoopDate {
            guard lastStartLoopDate.addingTimeInterval(Config.loopInterval) < Date() else {
                debug(.apsManager, "too close to do a loop : \(lastStartLoopDate)")
                return
            }
        }

        guard !isLooping.value else {
            warning(.apsManager, "Loop already in progress. Skip recommendation.")
            return
        }

        // start background time extension
        backGroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Loop starting") {
            guard let backgroundTask = self.backGroundTaskID else { return }
            UIApplication.shared.endBackgroundTask(backgroundTask)
            self.backGroundTaskID = .invalid
        }

        debug(.apsManager, "Starting loop with a delay of \(UIApplication.shared.backgroundTimeRemaining.rounded())")

        lastStartLoopDate = Date()

        var previousLoop = [LoopStatRecord]()
        var interval: Double?

        coredataContext.performAndWait {
            let requestStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            let sortStats = NSSortDescriptor(key: "end", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            try? previousLoop = coredataContext.fetch(requestStats)

            if (previousLoop.first?.end ?? .distantFuture) < lastStartLoopDate {
                interval = roundDouble((lastStartLoopDate - (previousLoop.first?.end ?? Date())).timeInterval / 60, 1)
            }
        }

        var loopStatRecord = LoopStats(
            start: lastStartLoopDate,
            loopStatus: "Starting",
            interval: interval
        )

        isLooping.send(true)
        determineBasal()
            .replaceEmpty(with: false)
            .flatMap { [weak self] success -> AnyPublisher<Void, Error> in
                guard let self = self, success else {
                    return Fail(error: APSError.apsError(message: "Determine basal failed")).eraseToAnyPublisher()
                }

                // Open loop completed
                guard self.settings.closedLoop else {
                    self.nightscout.uploadStatus()
                    return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
                }

                self.nightscout.uploadStatus()

                // Closed loop - enact suggested
                return self.enactSuggested()
            }
            .sink { [weak self] completion in
                guard let self = self else { return }
                loopStatRecord.end = Date()
                loopStatRecord.duration = self.roundDouble(
                    (loopStatRecord.end! - loopStatRecord.start).timeInterval / 60,
                    2
                )
                if case let .failure(error) = completion {
                    loopStatRecord.loopStatus = error.localizedDescription
                    self.loopCompleted(error: error, loopStatRecord: loopStatRecord)
                } else {
                    loopStatRecord.loopStatus = "Success"
                    self.loopCompleted(loopStatRecord: loopStatRecord)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    // Loop exit point
    private func loopCompleted(error: Error? = nil, loopStatRecord: LoopStats) {
        isLooping.send(false)

        // save AH events
        let events = pumpHistoryStorage.recent()
        healthKitManager.saveIfNeeded(pumpEvents: events)

        if let error = error {
            warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
            if let backgroundTask = backGroundTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundTaskID = .invalid
            }
            processError(error)
        } else {
            debug(.apsManager, "Loop succeeded")
            lastLoopDate = Date()
            lastError.send(nil)
        }

        loopStats(loopStatRecord: loopStatRecord)

        if settings.closedLoop {
            reportEnacted(received: error == nil)
        }

        // end of the BG tasks
        if let backgroundTask = backGroundTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backGroundTaskID = .invalid
        }
    }

    private func verifyStatus() -> Error? {
        guard let pump = pumpManager else {
            return APSError.invalidPumpState(message: "Pump not set")
        }
        let status = pump.status.pumpStatus

        guard !status.bolusing else {
            return APSError.invalidPumpState(message: "Pump is bolusing")
        }

        guard !status.suspended else {
            return APSError.invalidPumpState(message: "Pump suspended")
        }

        let reservoir = storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self) ?? 100
        guard reservoir >= 0 else {
            return APSError.invalidPumpState(message: "Reservoir is empty")
        }

        return nil
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
        guard let pump = pumpManager else { return amount }
        let rounded = Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
        let maxBolus = Decimal(pump.roundToSupportedBolusVolume(units: Double(settingsManager.pumpSettings.maxBolus)))
        return min(rounded, maxBolus)
    }

    private var bolusReporter: DoseProgressReporter?

    func enactBolus(amount: Double, isSMB: Bool) {
        if let error = verifyStatus() {
            processError(error)
            processQueue.async {
                self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                    $0.bolusDidFail()
                }
            }
            return
        }

        guard let pump = pumpManager else { return }

        let roundedAmout = pump.roundToSupportedBolusVolume(units: amount)

        debug(.apsManager, "Enact bolus \(roundedAmout), manual \(!isSMB)")

        pump.enactBolus(units: roundedAmout, automatic: isSMB).sink { completion in
            if case let .failure(error) = completion {
                warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
                if !isSMB {
                    self.processQueue.async {
                        self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                            $0.bolusDidFail()
                        }
                    }
                }
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
        if let error = verifyStatus() {
            processError(error)
            return
        }

        guard let pump = pumpManager else { return }

        // unable to do temp basal during manual temp basal 😁
        if isManualTempBasal {
            processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
            return
        }

        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")

        let roundedAmout = pump.roundToSupportedBasalRate(unitsPerHour: rate)
        pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration) { error in
            if let error = error {
                debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            } else {
                debug(.apsManager, "Temp Basal succeeded")
                let temp = TempBasal(duration: Int(duration / 60), rate: Decimal(rate), temp: .absolute, timestamp: Date())
                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                if rate == 0, duration == 0 {
                    self.pumpHistoryStorage.saveCancelTempEvents()
                }
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
            if let error = verifyStatus() {
                processError(error)
                return
            }
            let roundedAmount = pump.roundToSupportedBolusVolume(units: Double(amount))
            pump.enactBolus(units: roundedAmount, activationType: .manualRecommendationAccepted) { error in
                if let error = error {
                    // warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                    switch error {
                    case .uncertainDelivery:
                        // Do not generate notification on uncertain delivery error
                        break
                    default:
                        // Do not generate notifications for automatic boluses that fail.
                        warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                    }

                } else {
                    debug(.apsManager, "Announcement Bolus succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    self.bolusProgress.send(0)
                }
            }
        case let .pump(pumpAction):
            switch pumpAction {
            case .suspend:
                if let error = verifyStatus() {
                    processError(error)
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
            if let error = verifyStatus() {
                processError(error)
                return
            }
            // unable to do temp basal during manual temp basal 😁
            if isManualTempBasal {
                processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
                return
            }
            guard !settings.closedLoop else {
                return
            }
            let roundedRate = pump.roundToSupportedBasalRate(unitsPerHour: Double(rate))
            pump.enactTempBasal(unitsPerHour: roundedRate, for: TimeInterval(duration) * 60) { error in
                if let error = error {
                    warning(.apsManager, "Announcement TempBasal failed with error: \(error.localizedDescription)")
                } else {
                    debug(.apsManager, "Announcement TempBasal succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
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

    private func enactSuggested() -> AnyPublisher<Void, Error> {
        guard let suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) else {
            return Fail(error: APSError.apsError(message: "Suggestion not found")).eraseToAnyPublisher()
        }

        guard Date().timeIntervalSince(suggested.deliverAt ?? .distantPast) < Config.eхpirationInterval else {
            return Fail(error: APSError.apsError(message: "Suggestion expired")).eraseToAnyPublisher()
        }

        guard let pump = pumpManager else {
            return Fail(error: APSError.apsError(message: "Pump not set")).eraseToAnyPublisher()
        }

        // unable to do temp basal during manual temp basal 😁
        if isManualTempBasal {
            return Fail(error: APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
                .eraseToAnyPublisher()
        }

        let basalPublisher: AnyPublisher<Void, Error> = Deferred { () -> AnyPublisher<Void, Error> in
            if let error = self.verifyStatus() {
                return Fail(error: error).eraseToAnyPublisher()
            }

            guard let rate = suggested.rate, let duration = suggested.duration else {
                // It is OK, no temp required
                debug(.apsManager, "No temp required")
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactTempBasal(unitsPerHour: Double(rate), for: TimeInterval(duration * 60)).map { _ in
                let temp = TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: Date())
                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                return ()
            }
            .eraseToAnyPublisher()
        }.eraseToAnyPublisher()

        let bolusPublisher: AnyPublisher<Void, Error> = Deferred { () -> AnyPublisher<Void, Error> in
            if let error = self.verifyStatus() {
                return Fail(error: error).eraseToAnyPublisher()
            }
            guard let units = suggested.units else {
                // It is OK, no bolus required
                debug(.apsManager, "No bolus required")
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            return pump.enactBolus(units: Double(units), automatic: true).map { _ in
                self.bolusProgress.send(0)
                return ()
            }
            .eraseToAnyPublisher()
        }.eraseToAnyPublisher()

        return basalPublisher.flatMap { bolusPublisher }.eraseToAnyPublisher()
    }

    private func reportEnacted(received: Bool) {
        if let suggestion = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self), suggestion.deliverAt != nil {
            var enacted = suggestion
            enacted.timestamp = Date()
            enacted.recieved = received

            storage.save(enacted, as: OpenAPS.Enact.enacted)

            debug(.apsManager, "Suggestion enacted. Received: \(received)")
            DispatchQueue.main.async {
                self.broadcaster.notify(EnactedSuggestionObserver.self, on: .main) {
                    $0.enactedSuggestionDidUpdate(enacted)
                }
            }
            nightscout.uploadStatus()
            statistics()
        }
    }

    private func roundDecimal(_ decimal: Decimal, _ digits: Double) -> Decimal {
        let rounded = round(Double(decimal) * pow(10, digits)) / pow(10, digits)
        return Decimal(rounded)
    }

    private func roundDouble(_ double: Double, _ digits: Double) -> Double {
        let rounded = round(Double(double) * pow(10, digits)) / pow(10, digits)
        return rounded
    }

    private func medianCalculation(array: [Double]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    // Add to statistics.JSON
    private func statistics() {
        let now = Date()
        if settingsManager.settings.uploadStats {
            let hour = Calendar.current.component(.hour, from: now)
            guard hour > 20 else {
                return
            }
            coredataContext.performAndWait { [self] in
                var stats = [StatsData]()
                let requestStats = StatsData.fetchRequest() as NSFetchRequest<StatsData>
                let sortStats = NSSortDescriptor(key: "lastrun", ascending: false)
                requestStats.sortDescriptors = [sortStats]
                requestStats.fetchLimit = 1
                try? stats = coredataContext.fetch(requestStats)
                // Only save and upload once per day
                guard (-1 * (stats.first?.lastrun ?? .distantPast).timeIntervalSinceNow.hours) > 22 else { return }

                let units = self.settingsManager.settings.units
                let preferences = settingsManager.preferences

                var carbs = [Carbohydrates]()
                var carbTotal: Decimal = 0
                let requestCarbs = Carbohydrates.fetchRequest() as NSFetchRequest<Carbohydrates>
                let daysAgo = Date().addingTimeInterval(-1.days.timeInterval)
                requestCarbs.predicate = NSPredicate(format: "carbs > 0 AND date > %@", daysAgo as NSDate)

                let sortCarbs = NSSortDescriptor(key: "date", ascending: true)
                requestCarbs.sortDescriptors = [sortCarbs]
                try? carbs = coredataContext.fetch(requestCarbs)

                carbTotal = carbs.map({ carbs in carbs.carbs as? Decimal ?? 0 }).reduce(0, +)

                var tdds = [TDD]()
                var currentTDD: Decimal = 0
                var tddTotalAverage: Decimal = 0

                let requestTDD = TDD.fetchRequest() as NSFetchRequest<TDD>
                let sort = NSSortDescriptor(key: "timestamp", ascending: false)
                let daysOf14Ago = Date().addingTimeInterval(-14.days.timeInterval)
                requestTDD.predicate = NSPredicate(format: "timestamp > %@", daysOf14Ago as NSDate)
                requestTDD.sortDescriptors = [sort]
                try? tdds = coredataContext.fetch(requestTDD)

                if !tdds.isEmpty {
                    currentTDD = tdds[0].tdd?.decimalValue ?? 0
                    let tddArray = tdds.compactMap({ insulin in insulin.tdd as? Decimal ?? 0 })
                    tddTotalAverage = tddArray.reduce(0, +) / Decimal(tddArray.count)
                }

                var algo_ = "Oref0"

                if preferences.sigmoid, preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF + CR: Sigmoid"
                } else if preferences.sigmoid, !preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF: Sigmoid"
                } else if preferences.useNewFormula, preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF + CR: Logarithmic"
                } else if preferences.useNewFormula, !preferences.sigmoid,!preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF: Logarithmic"
                }

                let af = preferences.adjustmentFactor
                let insulin_type = preferences.curve
                let buildDate = Bundle.main.buildDate
                let version = Bundle.main.releaseVersionNumber
                let build = Bundle.main.buildVersionNumber
                let branch = Bundle.main.infoDictionary?["BuildBranch"] as? String ?? ""
                let copyrightNotice_ = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
                let pump_ = pumpManager?.localizedTitle ?? ""
                let cgm = settingsManager.settings.cgm
                let file = OpenAPS.Monitor.statistics
                var iPa: Decimal = 75
                if preferences.useCustomPeakTime {
                    iPa = preferences.insulinPeakTime
                } else if preferences.curve.rawValue == "rapid-acting" {
                    iPa = 65
                } else if preferences.curve.rawValue == "ultra-rapid" {
                    iPa = 50
                }

                var lsr = [LoopStatRecord]()

                let requestLSR = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
                requestLSR.predicate = NSPredicate(
                    format: "interval > 0 AND start > %@",
                    Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
                )
                let sortLSR = NSSortDescriptor(key: "start", ascending: false)
                requestLSR.sortDescriptors = [sortLSR]

                try? lsr = coredataContext.fetch(requestLSR)
                let loops = lsr

                let durationArray = loops.compactMap({ each in each.duration })
                let durationArrayCount = durationArray.count
                let successsNR = loops.compactMap({ each in each.loopStatus }).filter({ each in each!.contains("Success") }).count

                let durationAverage = durationArray.reduce(0, +) / Double(durationArrayCount)
                let medianDuration = medianCalculation(array: durationArray)
                let minimumDuration = durationArray.min() ?? 0
                let maximumDuration = durationArray.max() ?? 0
                let errorNR = durationArrayCount - successsNR
                let successRate: Double? = (Double(successsNR) / Double(successsNR + errorNR)) * 100
                let loopNr = successsNR + errorNR

                let intervalArray = loops.compactMap({ each in each.interval })
                let intervalArrayCount = intervalArray.count
                let intervalAverage = intervalArray.reduce(0, +) / Double(intervalArrayCount)
                let intervalMedian = medianCalculation(array: intervalArray)
                let maximumInterval = intervalArray.max() ?? 0
                let minimumInterval = intervalArray.min() ?? 0

                var glucose = [Readings]()

                var firstElementTime = Date()
                var lastElementTime = Date()
                var currentIndexTime = Date()

                var bg: Decimal = 0

                var bgArray: [Double] = []
                var bgArray_1_: [Double] = []
                var bgArray_7_: [Double] = []
                var bgArray_30_: [Double] = []

                var bgArrayForTIR: [(bg_: Double, date_: Date)] = []
                var bgArray_1: [(bg_: Double, date_: Date)] = []
                var bgArray_7: [(bg_: Double, date_: Date)] = []
                var bgArray_30: [(bg_: Double, date_: Date)] = []

                var medianBG = 0.0
                var nr_bgs: Decimal = 0
                var bg_1: Decimal = 0
                var bg_7: Decimal = 0
                var bg_30: Decimal = 0
                var bg_total: Decimal = 0
                var j = -1
                var conversionFactor: Decimal = 1
                if units == .mmolL {
                    conversionFactor = 0.0555
                }

                var numberOfDays: Double = 0
                var nr1: Decimal = 0

                let requestGFS = Readings.fetchRequest() as NSFetchRequest<Readings>
                let sortGlucose = NSSortDescriptor(key: "date", ascending: false)
                requestGFS.sortDescriptors = [sortGlucose]

                try? glucose = coredataContext.fetch(requestGFS)

                // Time In Range (%) and Average Glucose. This will be refactored later after some testing.
                let endIndex = glucose.count - 1

                firstElementTime = glucose[0].date ?? Date()
                lastElementTime = glucose[endIndex].date ?? Date()

                currentIndexTime = firstElementTime

                numberOfDays = (firstElementTime - lastElementTime).timeInterval / 8.64E4

                // Make arrays for median calculations and calculate averages
                if endIndex >= 0, (glucose.first?.glucose ?? 0) != 0 {
                    repeat {
                        j += 1
                        if glucose[j].glucose > 0 {
                            currentIndexTime = glucose[j].date ?? firstElementTime
                            bg += Decimal(glucose[j].glucose) * conversionFactor
                            bgArray.append(Double(glucose[j].glucose) * Double(conversionFactor))
                            bgArrayForTIR.append((Double(glucose[j].glucose), glucose[j].date!))
                            nr_bgs += 1
                            if (firstElementTime - currentIndexTime).timeInterval <= 8.64E4 { // 1 day
                                bg_1 = bg / nr_bgs
                                bgArray_1 = bgArrayForTIR
                                bgArray_1_ = bgArray
                                nr1 = nr_bgs
                            }
                            if (firstElementTime - currentIndexTime).timeInterval <= 6.048E5 { // 7 days
                                bg_7 = bg / nr_bgs
                                bgArray_7 = bgArrayForTIR
                                bgArray_7_ = bgArray
                            }
                            if (firstElementTime - currentIndexTime).timeInterval <= 2.592E6 { // 30 days
                                bg_30 = bg / nr_bgs
                                bgArray_30 = bgArrayForTIR
                                bgArray_30_ = bgArray
                            }
                        }
                    } while j != glucose.count - 1
                } else { return }

                if nr_bgs > 0 {
                    // Up to 91 days
                    bg_total = bg / nr_bgs
                }

                // Total median
                medianBG = medianCalculation(array: bgArray)

                func tir(_ array: [(bg_: Double, date_: Date)]) -> (TIR: Double, hypos: Double, hypers: Double) {
                    var timeInHypo = 0.0
                    var timeInHyper = 0.0
                    var hypos = 0.0
                    var hypers = 0.0
                    var i = -1
                    var lastIndex = false
                    let endIndex = array.count - 1

                    let hypoLimit = settingsManager.settings.low
                    let hyperLimit = settingsManager.settings.high

                    var full_time = 0.0
                    if endIndex > 0 {
                        full_time = (array[0].date_ - array[endIndex].date_).timeInterval
                    }
                    while i < endIndex {
                        i += 1
                        let currentTime = array[i].date_
                        var previousTime = currentTime
                        if i + 1 <= endIndex {
                            previousTime = array[i + 1].date_
                        } else {
                            lastIndex = true
                        }
                        if array[i].bg_ < Double(hypoLimit), !lastIndex {
                            // Exclude duration between CGM readings which are more than 30 minutes
                            timeInHypo += min((currentTime - previousTime).timeInterval, 30.minutes.timeInterval)
                        } else if array[i].bg_ >= Double(hyperLimit), !lastIndex {
                            timeInHyper += min((currentTime - previousTime).timeInterval, 30.minutes.timeInterval)
                        }
                    }
                    if timeInHypo == 0.0 {
                        hypos = 0
                    } else if full_time != 0.0 { hypos = (timeInHypo / full_time) * 100
                    }
                    if timeInHyper == 0.0 {
                        hypers = 0
                    } else if full_time != 0.0 { hypers = (timeInHyper / full_time) * 100
                    }
                    let TIR = 100 - (hypos + hypers)
                    return (roundDouble(TIR, 1), roundDouble(hypos, 1), roundDouble(hypers, 1))
                }

                // HbA1c estimation (%, mmol/mol) 1 day
                var NGSPa1CStatisticValue: Decimal = 0.0
                var IFCCa1CStatisticValue: Decimal = 0.0
                if nr_bgs > 0 {
                    NGSPa1CStatisticValue = ((bg_1 / conversionFactor) + 46.7) / 28.7 // NGSP (%)
                    IFCCa1CStatisticValue = 10.929 *
                        (NGSPa1CStatisticValue - 2.152) // IFCC (mmol/mol)  A1C(mmol/mol) = 10.929 * (A1C(%) - 2.15)
                }
                // 7 days
                var NGSPa1CStatisticValue_7: Decimal = 0.0
                var IFCCa1CStatisticValue_7: Decimal = 0.0
                if nr_bgs > 0 {
                    NGSPa1CStatisticValue_7 = ((bg_7 / conversionFactor) + 46.7) / 28.7
                    IFCCa1CStatisticValue_7 = 10.929 * (NGSPa1CStatisticValue_7 - 2.152)
                }
                // 30 days
                var NGSPa1CStatisticValue_30: Decimal = 0.0
                var IFCCa1CStatisticValue_30: Decimal = 0.0
                if nr_bgs > 0 {
                    NGSPa1CStatisticValue_30 = ((bg_30 / conversionFactor) + 46.7) / 28.7
                    IFCCa1CStatisticValue_30 = 10.929 * (NGSPa1CStatisticValue_30 - 2.152)
                }
                // Total days
                var NGSPa1CStatisticValue_total: Decimal = 0.0
                var IFCCa1CStatisticValue_total: Decimal = 0.0
                if nr_bgs > 0 {
                    NGSPa1CStatisticValue_total = ((bg_total / conversionFactor) + 46.7) / 28.7
                    IFCCa1CStatisticValue_total = 10.929 *
                        (NGSPa1CStatisticValue_total - 2.152)
                }

                let median = Durations(
                    day: roundDecimal(Decimal(medianCalculation(array: bgArray_1_)), 1),
                    week: roundDecimal(Decimal(medianCalculation(array: bgArray_7_)), 1),
                    month: roundDecimal(Decimal(medianCalculation(array: bgArray_30_)), 1),
                    total: roundDecimal(Decimal(medianBG), 1)
                )

                let saveMedianToCoreData = BGmedian(context: self.coredataContext)
                saveMedianToCoreData.date = Date()
                saveMedianToCoreData.median = median.total as NSDecimalNumber
                saveMedianToCoreData.median_1 = median.day as NSDecimalNumber
                saveMedianToCoreData.median_7 = median.week as NSDecimalNumber
                saveMedianToCoreData.median_30 = median.month as NSDecimalNumber

                try? self.coredataContext.save()

                var hbs = Durations(
                    day: roundDecimal(NGSPa1CStatisticValue, 1),
                    week: roundDecimal(NGSPa1CStatisticValue_7, 1),
                    month: roundDecimal(NGSPa1CStatisticValue_30, 1),
                    total: roundDecimal(NGSPa1CStatisticValue_total, 1)
                )

                let saveHbA1c = HbA1c(context: self.coredataContext)
                saveHbA1c.date = Date()
                saveHbA1c.hba1c = NGSPa1CStatisticValue_total as NSDecimalNumber
                saveHbA1c.hba1c_1 = NGSPa1CStatisticValue as NSDecimalNumber
                saveHbA1c.hba1c_7 = NGSPa1CStatisticValue_7 as NSDecimalNumber
                saveHbA1c.hba1c_30 = NGSPa1CStatisticValue_30 as NSDecimalNumber

                try? self.coredataContext.save()

                // Convert to user-preferred unit
                let overrideHbA1cUnit = settingsManager.settings.overrideHbA1cUnit
                if units == .mmolL {
                    // Override if users sets overrideHbA1cUnit: true
                    if !overrideHbA1cUnit {
                        hbs = Durations(
                            day: roundDecimal(IFCCa1CStatisticValue, 1),
                            week: roundDecimal(IFCCa1CStatisticValue_7, 1),
                            month: roundDecimal(IFCCa1CStatisticValue_30, 1),
                            total: roundDecimal(IFCCa1CStatisticValue_total, 1)
                        )
                    }
                } else if units != .mmolL, overrideHbA1cUnit {
                    hbs = Durations(
                        day: roundDecimal(IFCCa1CStatisticValue, 1),
                        week: roundDecimal(IFCCa1CStatisticValue_7, 1),
                        month: roundDecimal(IFCCa1CStatisticValue_30, 1),
                        total: roundDecimal(IFCCa1CStatisticValue_total, 1)
                    )
                }

                let nrOfCGMReadings = nr1

                let loopstat = LoopCycles(
                    loops: loopNr,
                    errors: errorNR,
                    readings: Int(nrOfCGMReadings),
                    success_rate: Decimal(round(successRate ?? 0)),
                    avg_interval: roundDecimal(Decimal(intervalAverage), 1),
                    median_interval: roundDecimal(Decimal(intervalMedian), 1),
                    min_interval: roundDecimal(Decimal(minimumInterval), 1),
                    max_interval: roundDecimal(Decimal(maximumInterval), 1),
                    avg_duration: Decimal(roundDouble(durationAverage, 2)),
                    median_duration: Decimal(roundDouble(medianDuration, 2)),
                    min_duration: roundDecimal(Decimal(minimumDuration), 2),
                    max_duration: Decimal(roundDouble(maximumDuration, 1))
                )

                // TIR calcs for every case
                var oneDay_: (TIR: Double, hypos: Double, hypers: Double) = (0.0, 0.0, 0.0)
                var sevenDays_: (TIR: Double, hypos: Double, hypers: Double) = (0.0, 0.0, 0.0)
                var thirtyDays_: (TIR: Double, hypos: Double, hypers: Double) = (0.0, 0.0, 0.0)
                var totalDays_: (TIR: Double, hypos: Double, hypers: Double) = (0.0, 0.0, 0.0)

                // Get all TIR calcs for every case
                if nr_bgs > 0 {
                    oneDay_ = tir(bgArray_1)
                    sevenDays_ = tir(bgArray_7)
                    thirtyDays_ = tir(bgArray_30)
                    totalDays_ = tir(bgArrayForTIR)
                }

                let tir = Durations(
                    day: roundDecimal(Decimal(oneDay_.TIR), 1),
                    week: roundDecimal(Decimal(sevenDays_.TIR), 1),
                    month: roundDecimal(Decimal(thirtyDays_.TIR), 1),
                    total: roundDecimal(Decimal(totalDays_.TIR), 1)
                )

                let hypo = Durations(
                    day: Decimal(oneDay_.hypos),
                    week: Decimal(sevenDays_.hypos),
                    month: Decimal(thirtyDays_.hypos),
                    total: Decimal(totalDays_.hypos)
                )

                let hyper = Durations(
                    day: Decimal(oneDay_.hypers),
                    week: Decimal(sevenDays_.hypers),
                    month: Decimal(thirtyDays_.hypers),
                    total: Decimal(totalDays_.hypers)
                )

                let range = Threshold(
                    low: units == .mmolL ? roundDecimal(settingsManager.settings.low.asMmolL, 1) :
                        roundDecimal(settingsManager.settings.low, 0),
                    high: units == .mmolL ? roundDecimal(settingsManager.settings.high.asMmolL, 1) :
                        roundDecimal(settingsManager.settings.high, 0)
                )

                let TimeInRange = TIRs(
                    TIR: tir,
                    Hypos: hypo,
                    Hypers: hyper,
                    Threshold: range
                )

                let avgs = Durations(
                    day: roundDecimal(bg_1, 1),
                    week: roundDecimal(bg_7, 1),
                    month: roundDecimal(bg_30, 1),
                    total: roundDecimal(bg_total, 1)
                )

                let saveAverages = BGaverages(context: self.coredataContext)
                saveAverages.date = Date()
                saveAverages.average = bg_total as NSDecimalNumber
                saveAverages.average_1 = bg_1 as NSDecimalNumber
                saveAverages.average_7 = bg_7 as NSDecimalNumber
                saveAverages.average_30 = bg_30 as NSDecimalNumber
                try? self.coredataContext.save()

                let avg = Averages(Average: avgs, Median: median)
                var insulinDistribution = [InsulinDistribution]()

                var insulin = Ins(
                    TDD: 0,
                    bolus: 0,
                    temp_basal: 0,
                    scheduled_basal: 0,
                    total_average: 0
                )

                let requestInsulinDistribution = InsulinDistribution.fetchRequest() as NSFetchRequest<InsulinDistribution>
                let sortInsulin = NSSortDescriptor(key: "date", ascending: false)
                requestInsulinDistribution.sortDescriptors = [sortInsulin]

                try? insulinDistribution = coredataContext.fetch(requestInsulinDistribution)

                insulin = Ins(
                    TDD: roundDecimal(currentTDD, 2),
                    bolus: insulinDistribution.first != nil ? ((insulinDistribution.first?.bolus ?? 0) as Decimal) : 0,
                    temp_basal: insulinDistribution.first != nil ? ((insulinDistribution.first?.tempBasal ?? 0) as Decimal) : 0,
                    scheduled_basal: insulinDistribution
                        .first != nil ? ((insulinDistribution.first?.scheduledBasal ?? 0) as Decimal) : 0,
                    total_average: roundDecimal(tddTotalAverage, 1)
                )

                var sumOfSquares = 0.0
                var sumOfSquares_1 = 0.0
                var sumOfSquares_7 = 0.0
                var sumOfSquares_30 = 0.0

                // Total
                for array in bgArray {
                    sumOfSquares += pow(array - Double(bg_total), 2)
                }
                // One day
                for array_1 in bgArray_1_ {
                    sumOfSquares_1 += pow(array_1 - Double(bg_1), 2)
                }
                // week
                for array_7 in bgArray_7_ {
                    sumOfSquares_7 += pow(array_7 - Double(bg_7), 2)
                }
                // month
                for array_30 in bgArray_30_ {
                    sumOfSquares_30 += pow(array_30 - Double(bg_30), 2)
                }

                // Standard deviation and Coefficient of variation
                var sd_total = 0.0
                var cv_total = 0.0
                var sd_1 = 0.0
                var cv_1 = 0.0
                var sd_7 = 0.0
                var cv_7 = 0.0
                var sd_30 = 0.0
                var cv_30 = 0.0

                // Avoid division by zero
                if bg_total > 0 {
                    sd_total = sqrt(sumOfSquares / Double(nr_bgs))
                    cv_total = sd_total / Double(bg_total) * 100
                }
                if bg_1 > 0 {
                    sd_1 = sqrt(sumOfSquares_1 / Double(bgArray_1_.count))
                    cv_1 = sd_1 / Double(bg_1) * 100
                }
                if bg_7 > 0 {
                    sd_7 = sqrt(sumOfSquares_7 / Double(bgArray_7_.count))
                    cv_7 = sd_7 / Double(bg_7) * 100
                }
                if bg_30 > 0 {
                    sd_30 = sqrt(sumOfSquares_30 / Double(bgArray_30_.count))
                    cv_30 = sd_30 / Double(bg_30) * 100
                }

                // Standard Deviations
                let standardDeviations = Durations(
                    day: roundDecimal(Decimal(sd_1), 1),
                    week: roundDecimal(Decimal(sd_7), 1),
                    month: roundDecimal(Decimal(sd_30), 1),
                    total: roundDecimal(Decimal(sd_total), 1)
                )

                // CV = standard deviation / sample mean x 100
                let cvs = Durations(
                    day: roundDecimal(Decimal(cv_1), 1),
                    week: roundDecimal(Decimal(cv_7), 1),
                    month: roundDecimal(Decimal(cv_30), 1),
                    total: roundDecimal(Decimal(cv_total), 1)
                )

                let variance = Variance(SD: standardDeviations, CV: cvs)

                let dailystat = Statistics(
                    created_at: Date(),
                    iPhone: UIDevice.current.getDeviceId,
                    iOS: UIDevice.current.getOSInfo,
                    Build_Version: version ?? "",
                    Build_Number: build ?? "1",
                    Branch: branch,
                    CopyRightNotice: String(copyrightNotice_.prefix(32)),
                    Build_Date: buildDate,
                    Algorithm: algo_,
                    AdjustmentFactor: af,
                    Pump: pump_,
                    CGM: cgm.rawValue,
                    insulinType: insulin_type.rawValue,
                    peakActivityTime: iPa,
                    Carbs_24h: carbTotal,
                    GlucoseStorage_Days: Decimal(roundDouble(numberOfDays, 1)),
                    Statistics: Stats(
                        Distribution: TimeInRange,
                        Glucose: avg,
                        HbA1c: hbs,
                        LoopCycles: loopstat,
                        Insulin: insulin,
                        Variance: variance
                    )
                )

                storage.save(dailystat, as: file)
                nightscout.uploadStatistics(dailystat: dailystat)
                nightscout.uploadPreferences()

                let saveStatsCoreData = StatsData(context: self.coredataContext)
                saveStatsCoreData.lastrun = Date()
                try? self.coredataContext.save()
                print("Test time of statistics computation: \(-1 * now.timeIntervalSinceNow) s")
            }
        }
    }

    private func loopStats(loopStatRecord: LoopStats) {
        let LoopStatsStartedAt = Date()

        coredataContext.perform {
            let nLS = LoopStatRecord(context: self.coredataContext)

            nLS.start = loopStatRecord.start
            nLS.end = loopStatRecord.end ?? Date()
            nLS.loopStatus = loopStatRecord.loopStatus
            nLS.duration = loopStatRecord.duration ?? 0.0
            nLS.interval = loopStatRecord.interval ?? 0.0

            try? self.coredataContext.save()
        }
        print("LoopStatRecords: \(loopStatRecord)")
        print("Test time of LoopStats computation: \(-1 * LoopStatsStartedAt.timeIntervalSinceNow) s")
    }

    private func processError(_ error: Error) {
        warning(.apsManager, "\(error.localizedDescription)")
        lastError.send(error)
    }

    private func createBolusReporter() {
        bolusReporter = pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
        bolusReporter?.addObserver(self)
    }

    private func updateStatus() {
        debug(.apsManager, "force update status")
        guard let pump = pumpManager else {
            return
        }

        if let omnipod = pump as? OmnipodPumpManager {
            omnipod.getPodStatus { _ in }
        }
        if let omnipodBLE = pump as? OmniBLEPumpManager {
            omnipodBLE.getPodStatus { _ in }
        }
    }

    private func clearBolusReporter() {
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        processQueue.asyncAfter(deadline: .now() + 0.5) {
            self.bolusProgress.send(nil)
            self.updateStatus()
        }
    }
}

private extension PumpManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            self.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
                if let error = error {
                    debug(.apsManager, "Temp basal failed: \(unitsPerHour) for: \(duration)")
                    promise(.failure(error))
                } else {
                    debug(.apsManager, "Temp basal succeded: \(unitsPerHour) for: \(duration)")
                    promise(.success(nil))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func enactBolus(units: Double, automatic: Bool) -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            // convert automatic
            let automaticValue = automatic ? BolusActivationType.automatic : BolusActivationType.manualRecommendationAccepted

            self.enactBolus(units: units, activationType: automaticValue) { error in
                if let error = error {
                    debug(.apsManager, "Bolus failed: \(units)")
                    promise(.failure(error))
                } else {
                    debug(.apsManager, "Bolus succeded: \(units)")
                    promise(.success(nil))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func cancelBolus() -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            self.cancelBolus { result in
                switch result {
                case let .success(dose):
                    debug(.apsManager, "Cancel Bolus succeded")
                    promise(.success(dose))
                case let .failure(error):
                    debug(.apsManager, "Cancel Bolus failed")
                    promise(.failure(error))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
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
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
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
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
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
