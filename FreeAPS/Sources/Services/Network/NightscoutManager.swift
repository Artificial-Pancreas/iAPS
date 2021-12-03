import Combine
import Foundation
import Swinject
import UIKit

protocol NightscoutManager: GlucoseSource {
    func fetchGlucose(since date: Date) -> AnyPublisher<[BloodGlucose], Never>
    func fetchCarbs() -> AnyPublisher<[CarbsEntry], Never>
    func fetchTempTargets() -> AnyPublisher<[TempTarget], Never>
    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never>
    func deleteCarbs(at date: Date)
    func uploadStatus()
    func uploadGlucose()
    var cgmURL: URL? { get }
}

final class BaseNightscoutManager: NightscoutManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var reachabilityManager: ReachabilityManager!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
    private var ping: TimeInterval?

    private var lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var isUploadEnabled: Bool {
        settingsManager.settings.isUploadEnabled
    }

    private var isUploadGlucoseEnabled: Bool {
        settingsManager.settings.uploadGlucose
    }

    private var nightscoutAPI: NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
        _ = reachabilityManager.startListening(onQueue: processQueue) { status in
            debug(.nightscout, "Network status: \(status)")
        }
    }

    func sourceInfo() -> [String: Any]? {
        if let ping = ping {
            return [GlucoseSourceKey.nightscoutPing.rawValue: ping]
        }
        return nil
    }

    var cgmURL: URL? {
        if let url = settingsManager.settings.cgm.appURL {
            return url
        }

        let useLocal = settingsManager.settings.useLocalGlucoseSource

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        return maybeNightscout?.url
    }

    func fetchGlucose(since date: Date) -> AnyPublisher<[BloodGlucose], Never> {
        let useLocal = settingsManager.settings.useLocalGlucoseSource
        ping = nil

        if !useLocal {
            guard isNetworkReachable else {
                return Just([]).eraseToAnyPublisher()
            }
        }

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        guard let nightscout = maybeNightscout else {
            return Just([]).eraseToAnyPublisher()
        }

        let startDate = Date()

        return nightscout.fetchLastGlucose(sinceDate: date)
            .tryCatch({ (error) -> AnyPublisher<[BloodGlucose], Error> in
                print(error.localizedDescription)
                return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
            })
            .replaceError(with: [])
            .handleEvents(receiveOutput: { value in
                guard value.isNotEmpty else { return }
                self.ping = Date().timeIntervalSince(startDate)
            })
            .eraseToAnyPublisher()
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        fetchGlucose(since: glucoseStorage.syncDate())
    }

    func fetchCarbs() -> AnyPublisher<[CarbsEntry], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = carbsStorage.syncDate()
        return nightscout.fetchCarbs(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func fetchTempTargets() -> AnyPublisher<[TempTarget], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = tempTargetsStorage.syncDate()
        return nightscout.fetchTempTargets(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = announcementsStorage.syncDate()
        return nightscout.fetchAnnouncement(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func deleteCarbs(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            carbsStorage.deleteCarbs(at: date)
            return
        }

        nightscout.deleteCarbs(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    self.carbsStorage.deleteCarbs(at: date)
                    debug(.nightscout, "Carbs deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func uploadStatus() {
        let iob = storage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        var suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        var enacted = storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)

        if (suggested?.timestamp ?? .distantPast) > (enacted?.timestamp ?? .distantPast) {
            enacted?.predictions = nil
        } else {
            suggested?.predictions = nil
        }

        let openapsStatus = OpenAPSStatus(
            iob: iob?.first,
            suggested: suggested,
            enacted: enacted,
            version: "0.7.0"
        )

        let battery = storage.retrieve(OpenAPS.Monitor.battery, as: Battery.self)
        var reservoir = Decimal(from: storage.retrieveRaw(OpenAPS.Monitor.reservoir) ?? "0")
        if reservoir == 0xDEAD_BEEF {
            reservoir = nil
        }
        let pumpStatus = storage.retrieve(OpenAPS.Monitor.status, as: PumpStatus.self)

        let pump = NSPumpStatus(clock: Date(), battery: battery, reservoir: reservoir, status: pumpStatus)

        let preferences = settingsManager.preferences

        let device = UIDevice.current

        let uploader = Uploader(batteryVoltage: nil, battery: Int(device.batteryLevel * 100))

        let status = NightscoutStatus(
            device: "freeaps-x://" + device.name,
            openaps: openapsStatus,
            pump: pump,
            preferences: preferences,
            uploader: uploader
        )

        storage.save(status, as: OpenAPS.Upload.nsStatus)

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.uploadStatus(status)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Status uploaded")
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadGlucose() {
        uploadGlucose(glucoseStorage.nightscoutGlucoseNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedGlucose)
    }

    private func uploadPumpHistory() {
        uploadTreatments(pumpHistoryStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedPumphistory)
    }

    private func uploadCarbs() {
        uploadTreatments(carbsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedCarbs)
    }

    private func uploadTempTargets() {
        uploadTreatments(tempTargetsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedTempTargets)
    }

    private func uploadGlucose(_ glucose: [BloodGlucose], fileToSave: String) {
        guard !glucose.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled, isUploadGlucoseEnabled else {
            return
        }

        processQueue.async {
            glucose.chunks(ofCount: 100)
                .map { chunk -> AnyPublisher<Void, Error> in
                    nightscout.uploadGlucose(Array(chunk))
                }
                .reduce(
                    Just(()).setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                ) { (result, next) -> AnyPublisher<Void, Error> in
                    Publishers.Concatenate(prefix: result, suffix: next).eraseToAnyPublisher()
                }
                .dropFirst()
                .sink { completion in
                    switch completion {
                    case .finished:
                        self.storage.save(glucose, as: fileToSave)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    private func uploadTreatments(_ treatments: [NigtscoutTreatment], fileToSave: String) {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            treatments.chunks(ofCount: 100)
                .map { chunk -> AnyPublisher<Void, Error> in
                    nightscout.uploadTreatments(Array(chunk))
                }
                .reduce(
                    Just(()).setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                ) { (result, next) -> AnyPublisher<Void, Error> in
                    Publishers.Concatenate(prefix: result, suffix: next).eraseToAnyPublisher()
                }
                .dropFirst()
                .sink { completion in
                    switch completion {
                    case .finished:
                        self.storage.save(treatments, as: fileToSave)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }
}

extension BaseNightscoutManager: PumpHistoryObserver {
    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        uploadPumpHistory()
    }
}

extension BaseNightscoutManager: CarbsObserver {
    func carbsDidUpdate(_: [CarbsEntry]) {
        uploadCarbs()
    }
}

extension BaseNightscoutManager: TempTargetsObserver {
    func tempTargetsDidUpdate(_: [TempTarget]) {
        uploadTempTargets()
    }
}
