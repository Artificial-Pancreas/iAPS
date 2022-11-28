import Combine
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
        guard !isLooping.value else {
            warning(.apsManager, "Already looping, skip")
            return
        }

        debug(.apsManager, "Starting loop")

        var loopStatRecord = LoopStats(
            start: Date(),
            loopStatus: "Starting"
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

        if let error = error {
            warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
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

            // Create a tdd.json
            tdd(enacted_: enacted)

            // Create a dailyStats.json
            dailyStats()

            debug(.apsManager, "Suggestion enacted. Received: \(received)")
            DispatchQueue.main.async {
                self.broadcaster.notify(EnactedSuggestionObserver.self, on: .main) {
                    $0.enactedSuggestionDidUpdate(enacted)
                }
            }
            nightscout.uploadStatus()
        }
    }

    private func tdd(enacted_: Suggestion) {
        // Add to tdd.json:
        let preferences = settingsManager.preferences
        let currentTDD = enacted_.tdd ?? 0
        let file = OpenAPS.Monitor.tdd
        let tdd = TDD(
            TDD: currentTDD,
            timestamp: Date(),
            id: UUID().uuidString
        )
        var uniqEvents: [TDD] = []
        storage.transaction { storage in
            storage.append(tdd, to: file, uniqBy: \.id)
            uniqEvents = storage.retrieve(file, as: [TDD].self)?
                .filter { $0.timestamp.addingTimeInterval(14.days.timeInterval) > Date() }
                .sorted { $0.timestamp > $1.timestamp } ?? []
            var total: Decimal = 0
            var indeces: Decimal = 0
            for uniqEvent in uniqEvents {
                if uniqEvent.TDD > 0 {
                    total += uniqEvent.TDD
                    indeces += 1
                }
            }
            let entriesPast2hours = storage.retrieve(file, as: [TDD].self)?
                .filter { $0.timestamp.addingTimeInterval(2.hours.timeInterval) > Date() }
                .sorted { $0.timestamp > $1.timestamp } ?? []
            var totalAmount: Decimal = 0
            var nrOfIndeces: Decimal = 0
            for entry in entriesPast2hours {
                if entry.TDD > 0 {
                    totalAmount += entry.TDD
                    nrOfIndeces += 1
                }
            }
            if indeces == 0 {
                indeces = 1
            }
            if nrOfIndeces == 0 {
                nrOfIndeces = 1
            }
            let average14 = total / indeces
            let average2hours = totalAmount / nrOfIndeces
            let weight = preferences.weightPercentage
            let weighted_average = weight * average2hours + (1 - weight) * average14
            let averages = TDD_averages(
                average_total_data: roundDecimal(average14, 1),
                weightedAverage: roundDecimal(weighted_average, 1),
                past2hoursAverage: roundDecimal(average2hours, 1),
                date: Date()
            )
            storage.save(averages, as: OpenAPS.Monitor.tdd_averages)
            storage.save(Array(uniqEvents), as: file)
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
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2.0
        }
        return Double(sorted[length / 2])
    }

    // Add to dailyStats.JSON
    private func dailyStats() {
        var testFile: [DailyStats] = []
        var testIfEmpty = 0
        storage.transaction { storage in
            testFile = storage.retrieve(OpenAPS.Monitor.dailyStats, as: [DailyStats].self) ?? []
            testIfEmpty = testFile.count
        }
        // Only run every hour
        if testIfEmpty != 0 {
            guard testFile[0].createdAt.addingTimeInterval(1.hours.timeInterval) < Date() else {
                return
            }
        }

        let preferences = settingsManager.preferences
        let carbs = storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self)
        let tdds = storage.retrieve(OpenAPS.Monitor.tdd, as: [TDD].self)
        var currentTDD: Decimal = 0

        if tdds?.count ?? 0 > 0 {
            currentTDD = tdds?[0].TDD ?? 0
        }

        let carbs_length = carbs?.count ?? 0
        var carbTotal: Decimal = 0

        if carbs_length != 0 {
            for each in carbs! {
                if each.carbs != 0 {
                    carbTotal += each.carbs
                }
            }
        }

        var algo_ = "oref0" // Default
        if preferences.enableChris, preferences.useNewFormula {
            algo_ = "Dynamic ISF, Logarithmic Formula"
        } else if !preferences.useNewFormula, preferences.enableChris {
            algo_ = "Dynamic ISF, Original Formula"
        }
        let af = preferences.adjustmentFactor
        let insulin_type = preferences.curve
        let buildDate = Bundle.main.buildDate
        let version = Bundle.main.releaseVersionNumber
        let build = Bundle.main.buildVersionNumber
        let branch = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
        let pump_ = pumpManager?.localizedTitle ?? ""
        let cgm = settingsManager.settings.cgm
        let file = OpenAPS.Monitor.dailyStats
        var iPa: Decimal = 75
        if preferences.useCustomPeakTime {
            iPa = preferences.insulinPeakTime
        } else if preferences.curve.rawValue == "rapid-acting" {
            iPa = 65
        } else if preferences.curve.rawValue == "ultra-rapid" {
            iPa = 50
        }

        // Retrieve the loopStats data
        let lsData = storage.retrieve(OpenAPS.Monitor.loopStats, as: [LoopStats].self)?
            .sorted { $0.start > $1.start } ?? []

        var successRate: Double?
        var successNR = 0.0
        var errorNR = 0.0
        var minimumInt = 999.0
        var maximumInt = 0.0
        var minimumLoopTime = 9999.0
        var maximumLoopTime = 0.0
        var timeIntervalLoops = 0.0
        var previousTimeLoop = Date()
        var timeForOneLoop = 0.0
        var averageLoopTime = 0.0
        var timeForOneLoopArray: [Double] = []
        var medianLoopTime = 0.0
        var timeIntervalLoopArray: [Double] = []
        var medianInterval = 0.0
        var averageIntervalLoops = 0.0

        if !lsData.isEmpty {
            var i = 0.0

            if let loopEnd = lsData[0].end {
                previousTimeLoop = loopEnd
            }

            for each in lsData {
                if let loopEnd = each.end, let loopDuration = each.duration {
                    if each.loopStatus.contains("Success") {
                        successNR += 1
                    } else {
                        errorNR += 1
                    }
                    i += 1

                    timeIntervalLoops = (previousTimeLoop - each.start).timeInterval / 60
                    if timeIntervalLoops > 0.0, i != 1 {
                        timeIntervalLoopArray.append(timeIntervalLoops)
                    }

                    if timeIntervalLoops > maximumInt {
                        maximumInt = timeIntervalLoops
                    }
                    if timeIntervalLoops < minimumInt, i != 1 {
                        minimumInt = timeIntervalLoops
                    }

                    timeForOneLoop = loopDuration

                    timeForOneLoopArray.append(timeForOneLoop)
                    averageLoopTime += timeForOneLoop

                    if timeForOneLoop >= maximumLoopTime, timeForOneLoop != 0.0 {
                        maximumLoopTime = timeForOneLoop
                    }

                    if timeForOneLoop <= minimumLoopTime, timeForOneLoop != 0.0 {
                        minimumLoopTime = timeForOneLoop
                    }

                    previousTimeLoop = loopEnd
                }
            }

            successRate = (successNR / Double(i)) * 100

            averageIntervalLoops = ((lsData[0].end ?? lsData[lsData.count - 1].start) - lsData[lsData.count - 1].start)
                .timeInterval / 60 / Double(i)

            averageLoopTime /= Double(i)
            // Median values
            medianLoopTime = medianCalculation(array: timeForOneLoopArray)
            medianInterval = medianCalculation(array: timeIntervalLoopArray)
        }

        if minimumInt == 999.0 {
            minimumInt = 0.0
        }

        if minimumLoopTime == 9999.0 {
            minimumLoopTime = 0.0
        }

        // Time In Range (%) and Average Glucose (24 hours). This looks dumb and I will refactor it later.
        let glucose = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)

        let length_ = glucose?.count ?? 0
        let endIndex = length_ - 1
        var oneDayGlucoseIndex = endIndex

        var bg: Decimal = 0
        var bgArray: [Double] = []
        var medianBG = 0.0
        var nr_bgs: Decimal = 0
        let startDate = glucose![0].date
        var end1 = false
        var end7 = false
        var end10 = false
        var bg_1: Decimal = 0
        var bg_7: Decimal = 0
        var bg_10: Decimal = 0
        var bg_total: Decimal = 0
        var j = -1

        if length_ != 0 {
            for entry in glucose! {
                j += 1
                if entry.glucose! > 0 {
                    bg += Decimal(entry.glucose!)
                    bgArray.append(Double(entry.glucose!))
                    nr_bgs += 1

                    if startDate - entry.date >= 8.64E7, !end1 {
                        end1 = true
                        oneDayGlucoseIndex = j
                        bg_1 = bg / nr_bgs
                    }

                    if startDate - entry.date >= 6.045E8, !end7 {
                        end7 = true
                        bg_7 = bg / nr_bgs
                    }

                    if startDate - entry.date >= 8.64E8, !end10 {
                        end10 = true
                        bg_10 = bg / nr_bgs
                    }
                }
            }
        }

        if nr_bgs != 0 {
            bg_total = bg / nr_bgs
        }

        medianBG = medianCalculation(array: bgArray)

        let fullTime = glucose![0].date - glucose![endIndex].date
        let fullTime_1 = glucose![0].date - glucose![oneDayGlucoseIndex].date

        var daysBG = fullTime / 8.64E7

        var timeInHypo: Decimal = 0
        var timeInHyper: Decimal = 0
        var hypos: Decimal = 0
        var hypers: Decimal = 0
        var i = -1
        var lastIndex = false

        while i < endIndex {
            i += 1

            let currentTime = glucose![i].date
            var previousTime = currentTime

            if i + 1 <= endIndex {
                previousTime = glucose![i + 1].date
            } else {
                lastIndex = true
            }

            if glucose![i].glucose! < 72, !lastIndex {
                timeInHypo += currentTime - previousTime
            } else if glucose![i].glucose! > 180, !lastIndex {
                timeInHyper += currentTime - previousTime
            }
        }

        if timeInHypo == 0 {
            hypos = 0
        } else { hypos = (timeInHypo / fullTime) * 100
        }

        if timeInHyper == 0 {
            hypers = 0
        } else { hypers = (timeInHyper / fullTime) * 100
        }

        let TIR = 100 - (hypos + hypers)

        // Do the loop again but with for 1 day. I will change this later, because this looks really dumb:
        var timeInHypo_1: Decimal = 0
        var timeInHyper_1: Decimal = 0
        var hypos_1: Decimal = 0
        var hypers_1: Decimal = 0
        i = -1
        lastIndex = false

        while i < oneDayGlucoseIndex {
            i += 1

            let currentTime = glucose![i].date
            var previousTime = currentTime

            if i + 1 <= oneDayGlucoseIndex {
                previousTime = glucose![i + 1].date
            } else {
                lastIndex = true
            }

            if glucose![i].glucose! < 72, !lastIndex {
                timeInHypo_1 += currentTime - previousTime
            } else if glucose![i].glucose! > 180, !lastIndex {
                timeInHyper_1 += currentTime - previousTime
            }
        }

        if timeInHypo_1 == 0 {
            hypos_1 = 0
        } else { hypos_1 = (timeInHypo_1 / fullTime_1) * 100
        }

        if timeInHyper_1 == 0 {
            hypers_1 = 0
        } else { hypers_1 = (timeInHyper_1 / fullTime_1) * 100
        }

        let TIR_1 = 100 - (hypos_1 + hypers_1)

        // Add 10 day average to tenDaysStats.json
        let file_10 = OpenAPS.Monitor.tenDaysStats
        // let tensDaysStats = storage.retrieve(file_10, as: [TenDaysStats].self)

        let tenStats = TenDaysStats(
            createdAt: Date(), past10daysAverage: roundDecimal(bg_10, 1)
        )
        var uniqEvents: [TenDaysStats] = []
        var test1 = uniqEvents
        let test2: [TenDaysStats] = [tenStats]
        var countIndeces = 0

        storage.transaction { storage in
            test1 = storage.retrieve(file_10, as: [TenDaysStats].self) ?? []
            countIndeces = test1.count
        }

        if daysBG >= 10 {
            if countIndeces == 0 {
                storage.transaction { storage in
                    storage.save(test2, as: file_10)
                }

                // Keep 10 days apart from each array
            } else if test1[0].createdAt.addingTimeInterval(10.days.timeInterval) < Date() {
                storage.transaction { storage in
                    storage.append(tenStats, to: file_10, uniqBy: \.createdAt)
                    uniqEvents = storage.retrieve(file_10, as: [TenDaysStats].self)?
                        .filter { $0.createdAt.addingTimeInterval(365.days.timeInterval) > Date() }
                        .sorted { $0.createdAt > $1.createdAt } ?? []
                    storage.save(Array(uniqEvents), as: file_10)
                }
            }
        }

        // Retrieve the 10 days data array
        let uniqEvents_1 = storage.retrieve(OpenAPS.Monitor.tenDaysStats, as: [TenDaysStats].self)?
            .filter { $0.createdAt.addingTimeInterval(365.days.timeInterval) > Date() }
            .sorted { $0.createdAt > $1.createdAt } ?? []

        var index = 0
        var total: Decimal = 0
        var thirtyDays: Decimal = 0
        var ninetyDays: Decimal = 0

        for uniqEvent in uniqEvents_1 {
            if uniqEvent.past10daysAverage != 0 {
                total += uniqEvent.past10daysAverage
                index += 1
            }
            if index == 3 {
                thirtyDays = total / 3
            }
            if index == 9 {
                ninetyDays = total / 9
            }
        }

        // HbA1c estimation (%, mmol/mol)
        let NGSPa1CStatisticValue = (46.7 + bg_1) / 28.7 // NGSP (%)
        let IFCCa1CStatisticValue = 10.929 *
            (NGSPa1CStatisticValue - 2.152) // IFCC (mmol/mol)  A1C(mmol/mol) = 10.929 * (A1C(%) - 2.15)
        // 7 days
        let NGSPa1CStatisticValue_7 = (46.7 + bg_7) / 28.7
        let IFCCa1CStatisticValue_7 = 10.929 * (NGSPa1CStatisticValue_7 - 2.152)
        // 30 days
        let NGSPa1CStatisticValue_30 = (46.7 + thirtyDays) / 28.7
        let IFCCa1CStatisticValue_30 = 10.929 * (NGSPa1CStatisticValue_30 - 2.152)
        // Total days (up t0 10 days)
        let NGSPa1CStatisticValue_total = (46.7 + bg_total) / 28.7
        let IFCCa1CStatisticValue_total = 10.929 * (NGSPa1CStatisticValue_total - 2.152)
        // 90 Days
        let NGSPa1CStatisticValue_90 = (46.7 + ninetyDays) / 28.7
        let IFCCa1CStatisticValue_90 = 10.929 * (NGSPa1CStatisticValue_90 - 2.152)

        // HbA1c string and BG string:
        var HbA1c_string_1 = ""
        var string7Days = ""
        var string30Days = ""
        var string90Days = ""
        var stringTotal = ""
        var bgString1day = ""
        var bgString7Days = ""
        var bgString30Days = ""
        var bgString90Days = ""
        var bgAverageTotalString = ""

        // round output values
        daysBG = roundDecimal(daysBG, 1)

        if bg_1 != 0 {
            bgString1day =
                " Average BG (mmol/l) 24 hours): \(roundDecimal(bg_1 * 0.0555, 1)). Average BG (mmg/dl) 24 hours: \(roundDecimal(bg_1, 0))."
            HbA1c_string_1 =
                "Estimated HbA1c (mmol/mol, 1 day): \(roundDecimal(IFCCa1CStatisticValue, 1)). Estimated HbA1c (%, 1 day): \(roundDecimal(NGSPa1CStatisticValue, 1)). "
        }
        if bg_7 != 0 {
            string7Days =
                " HbA1c 7 days (mmol/mol): \(roundDecimal(IFCCa1CStatisticValue_7, 1)). HbA1c 7 days (%): \(roundDecimal(NGSPa1CStatisticValue_7, 1))."
            bgString7Days =
                " Average BG (mmol/l) 7 days: \(roundDecimal(bg_7 * 0.0555, 1)). Average BG (mg/dl) 7 days: \(roundDecimal(bg_7, 0))."
        }
        if thirtyDays != 0 {
            string30Days =
                " HbA1c 30 days (mmol/mol): \(roundDecimal(IFCCa1CStatisticValue_30, 1)).  HbA1c 30 days (%): \(roundDecimal(NGSPa1CStatisticValue_30, 1))."
            bgString30Days =
                " Average BG 30 days (mmol/l): \(roundDecimal(thirtyDays * 0.0555, 1)). Average BG 30 days (mg/dl): \(roundDecimal(thirtyDays, 0)). "
        }
        if ninetyDays != 0 {
            string90Days =
                " HbA1c 90 days (mmol/mol): \(roundDecimal(IFCCa1CStatisticValue_90, 1)).  HbA1c 90 days (%): \(roundDecimal(NGSPa1CStatisticValue_90, 1))."
            bgString90Days =
                " Average BG 90 days (mmol/l): \(roundDecimal(ninetyDays * 0.0555, 1)). Average BG 90 days (mg/dl): \(roundDecimal(ninetyDays, 0)). "
        }

        if bg_total != 0, daysBG >= 2 {
            stringTotal =
                " HbA1c Total (\(daysBG)) Days (mmol/mol): \(roundDecimal(IFCCa1CStatisticValue_total, 1)). HbA1c Total (\(daysBG)) Days (mg/dl): \(roundDecimal(NGSPa1CStatisticValue_total, 1)) %."
            bgAverageTotalString =
                " BG Median Total (\(daysBG)) Days (mmol/l): \(roundDouble(medianBG * 0.0555, 1)). BG Median Total (\(daysBG)) Days (mg/dl): \(roundDouble(medianBG, 0)). BG Average Total (\(daysBG)) Days (mmg/dl): \(roundDecimal(bg_total, 0))."
        }

        let HbA1c_string = HbA1c_string_1 + string7Days + string30Days + string90Days + stringTotal

        var tirString =
            "TIR (24 hours): \(roundDecimal(TIR_1, 0)) %. Time with Hypoglycaemia: \(roundDecimal(hypos_1, 0)) % (< 4 / 72). Time with Hyperglycaemia:  \(roundDecimal(hypers_1, 0)) % (> 10 / 180)."

        if daysBG >= 2 {
            tirString +=
                " Total days (\(daysBG) TIR: \(roundDecimal(TIR, 1)) %. Time with Hypoglycaemia: \(roundDecimal(hypos, 1)) % (< 4 / 72). Time with Hyperglycaemia: \(roundDecimal(hypers, 1)) % (> 10 / 180)."
        }

        let bgAverageString = bgString1day + bgString7Days + bgString30Days + bgString90Days + bgAverageTotalString

        let loopstat = LoopCycles(
            success_rate: Decimal(round(successRate ?? 0)),
            loops: Int(successNR + errorNR),
            errors: Int(errorNR),
            median_interval: roundDecimal(Decimal(medianInterval), 1),
            avg_interval: roundDecimal(Decimal(averageIntervalLoops), 1),
            min_interval: roundDecimal(Decimal(minimumInt), 1),
            max_interval: roundDecimal(Decimal(maximumInt), 1),
            median_duration: roundDecimal(Decimal(medianLoopTime), 2),
            avg_duration: roundDecimal(Decimal(averageLoopTime), 2),
            min_duration: roundDecimal(Decimal(minimumLoopTime), 2),
            max_duration: roundDecimal(Decimal(maximumLoopTime), 2)
        )

        let dailystat = DailyStats(
            createdAt: Date(),
            iPhone: UIDevice.current.getDeviceId,
            iOS: UIDevice.current.getOSInfo,
            Build_Version: version ?? "",
            Build_Number: build ?? "1",
            Branch: branch ?? "N/A",
            Build_Date: buildDate,
            Algorithm: algo_,
            AdjustmentFactor: af,
            Pump: pump_,
            CGM: cgm.rawValue,
            insulinType: insulin_type.rawValue,
            peakActivityTime: iPa,
            TDD: roundDecimal(currentTDD, 2),
            Carbs_24h: carbTotal,
            TIR: tirString,
            BG_Average: bgAverageString,
            HbA1c: HbA1c_string,
            LoopStats: [loopstat]
        )

        var uniqeEvents: [DailyStats] = []

        storage.transaction { storage in
            storage.append(dailystat, to: file, uniqBy: \.createdAt)
            uniqeEvents = storage.retrieve(file, as: [DailyStats].self)?
                .filter { $0.createdAt.addingTimeInterval(24.hours.timeInterval) > Date() }
                .sorted { $0.createdAt > $1.createdAt } ?? []

            storage.save(Array(uniqeEvents), as: file)
        }
    }

    private func loopStats(loopStatRecord: LoopStats) {
        let file = OpenAPS.Monitor.loopStats

        var uniqEvents: [LoopStats] = []

        storage.transaction { storage in
            storage.append(loopStatRecord, to: file, uniqBy: \.start)
            uniqEvents = storage.retrieve(file, as: [LoopStats].self)?
                .filter { $0.start.addingTimeInterval(24.hours.timeInterval) > Date() }
                .sorted { $0.start > $1.start } ?? []

            storage.save(Array(uniqEvents), as: file)
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
