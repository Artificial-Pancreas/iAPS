import Combine
import Foundation
import Swinject

protocol NightscoutManager {
    func fetchGlucose() -> AnyPublisher<Void, Never>
    func fetchCarbs() -> AnyPublisher<Void, Never>
    func fetchTempTargets() -> AnyPublisher<Void, Never>
    func fetchAnnouncements() -> AnyPublisher<Void, Never>
    func upload()
}

final class BaseNightscoutManager: NightscoutManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")

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

    func upload() {}

    private func uploadStatus() {}

    private func uploadTreatments() {}

    private func uploadPumphistory() {}
}
