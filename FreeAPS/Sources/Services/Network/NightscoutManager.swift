import Combine
import Foundation
import Swinject

protocol NightscoutManager {
    func fetchGlucose() -> AnyPublisher<Void, Never>
    func fetchCarbs() -> AnyPublisher<Void, Never>
    func fetchTempTargets() -> AnyPublisher<Void, Never>
    func fetchAnnouncements() -> AnyPublisher<Void, Never>
}

final class BaseNightscoutManager: NightscoutManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var broadcaster: Broadcaster!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")

    private var lifetime = Set<AnyCancellable>()

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
    }

    func fetchGlucose() -> AnyPublisher<Void, Never> {
        guard let nightscout = nightscoutAPI else {
            return Just(()).eraseToAnyPublisher()
        }

        let since = glucoseStorage.syncDate()
        return nightscout.fetchLastGlucose(288, sinceDate: since)
            .replaceError(with: [])
            .map {
                self.glucoseStorage.storeGlucose($0)
                return ()
            }
            .eraseToAnyPublisher()
    }

    func fetchCarbs() -> AnyPublisher<Void, Never> {
        guard let nightscout = nightscoutAPI else {
            return Just(()).eraseToAnyPublisher()
        }

        let since = carbsStorage.syncDate()
        return nightscout.fetchCarbs(sinceDate: since)
            .replaceError(with: [])
            .map {
                self.carbsStorage.storeCarbs($0)
                return ()
            }.eraseToAnyPublisher()
    }

    func fetchTempTargets() -> AnyPublisher<Void, Never> {
        guard let nightscout = nightscoutAPI else {
            return Just(()).eraseToAnyPublisher()
        }

        let since = tempTargetsStorage.syncDate()
        return nightscout.fetchTempTargets(sinceDate: since)
            .replaceError(with: [])
            .map {
                self.tempTargetsStorage.storeTempTargets($0)
                return ()
            }.eraseToAnyPublisher()
    }

    func fetchAnnouncements() -> AnyPublisher<Void, Never> {
        guard let nightscout = nightscoutAPI else {
            return Just(()).eraseToAnyPublisher()
        }

        let since = announcementsStorage.syncDate()
        return nightscout.fetchAnnouncement(sinceDate: since)
            .replaceError(with: [])
            .map {
                self.announcementsStorage.storeAnnouncements($0, enacted: false)
                return ()
            }.eraseToAnyPublisher()
    }

    private func uploadStatus() {}

    private func uploadPumpHistory() {
        uploadTreatments(pumpHistoryStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedPumphistory)
    }

    private func uploadCarbs() {
        uploadTreatments(carbsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedCarbs)
    }

    private func uploadTempTargets() {
        uploadTreatments(tempTargetsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedTempTargets)
    }

    private func uploadTreatments(_ treatments: [NigtscoutTreatment], fileToSave: String) {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI else {
            return
        }

        processQueue.async {
            nightscout.uploadTreatments(treatments)
                .sink { completion in
                    switch completion {
                    case .finished:
                        try? self.storage.save(treatments, as: fileToSave)
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
