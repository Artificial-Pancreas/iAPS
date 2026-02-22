import Combine
import CommonCrypto
import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI

private extension String {
    func sha1() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}

extension PumpConfig {
    enum ActionConfirmation: Int, Identifiable {
        case siteChange
        case reservoirChange
        case deleteSiteChange
        case deleteReservoirChange
        case forceSync
        var id: Int { rawValue }
    }

    enum InsulinAgeSource: String, CaseIterable, Identifiable {
        case pump = "Dana (Pump History)"
        case iaps = "iAPS (locally stored)"
        case nightscout = "Nightscout"
        var id: String { rawValue }
    }

    @MainActor final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() var keychain: Keychain!
        @Injected() var storage: FileStorage!

        @Published var pumpSetupPresented: Bool = false
        @Published private(set) var pumpIdentifierToSetUp: String? = nil
        @Published var pumpManagerStatus: PumpManagerStatus? = nil
        @Published var changedAt = Date()
        @Published var showUploadMessage: Bool = false
        @Published var uploadMessageText: String = ""
        @Published var confirmation: ActionConfirmation? = nil
        @Published var detectedDiscrepancyDate: Date? = nil

        private(set) var initialSettings: PumpInitialSettings = .default
        @Published var alertNotAck: Bool = false

        @Published var pumpInsulinAge: Date? = nil
        @Published var iapsInsulinAge: Date? = nil
        @Published var nightscoutInsulinAge: Date? = nil
        @Published var showInsulinAgeMismatch: Bool = false
        @Published var isSyncingInsulinAge: Bool = false

        var formattedChangedAt: String { formatDate(changedAt) }

        func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        override func subscribe() {
            Task { @MainActor in
                self.alertNotAck = self.provider.initialAlertNotAck()

                self.deviceManager.pumpManagerStatus
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        self?.pumpManagerStatus = status
                    }
                    .store(in: &self.lifetime)

                let basalSchedule = BasalRateSchedule(
                    dailyItems: self.provider.basalProfile().map {
                        RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                    }
                )

                let pumpSettings = self.provider.pumpSettings()
                self.initialSettings = PumpInitialSettings(
                    maxBolusUnits: Double(pumpSettings.maxBolus),
                    maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                    basalSchedule: basalSchedule!
                )
            }

            provider.alertNotAck
                .receive(on: DispatchQueue.main)
                .sink { [weak self] val in
                    Task { @MainActor in self?.alertNotAck = val }
                }
                .store(in: &lifetime)
        }

        func setupPump(_ identifier: String?) {
            pumpIdentifierToSetUp = identifier
            pumpSetupPresented = identifier != nil
        }

        func ack() {
            provider.deviceManager.alertHistoryStorage.forceNotification()
        }

        private var nightscoutAPI: NightscoutAPI? {
            guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                  let url = URL(string: urlString),
                  let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey) else { return nil }
            return NightscoutAPI(url: url, secret: secret)
        }

        private func showFeedback(message: String) {
            uploadMessageText = message
            withAnimation(.spring()) { showUploadMessage = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut) { self.showUploadMessage = false }
            }
        }

        func checkForDiscrepancy() {
            let lastLocalReset = storage.retrieve("monitor/reservoir.json", as: Date.self)
            if let localDate = lastLocalReset {
                let diff = abs(changedAt.timeIntervalSince(localDate))
                detectedDiscrepancyDate = (diff > 15 * 60) ? localDate : nil
            }
        }

        func forceInternalSync() {
            storage.save(changedAt, as: "monitor/reservoir.json")
            storage.save(changedAt, as: OpenAPS.Monitor.podAge)
            showFeedback(message: "App intern synchronisiert!")
        }

        func logSiteChange() {
            storage.save(changedAt, as: OpenAPS.Monitor.podAge)

            let treatment = NigtscoutTreatment(
                duration: nil, rawDuration: nil, rawRate: nil, absolute: nil, rate: nil,
                eventType: .nsSiteChange,
                createdAt: changedAt,
                enteredBy: "iAPS",
                bolus: nil, insulin: nil, notes: "Site Change", carbs: nil, fat: nil, protein: nil,
                targetTop: nil, targetBottom: nil
            )

            let treatments: [NigtscoutTreatment] = [treatment]
            storage.save(treatments, as: OpenAPS.Nightscout.uploadedPodAge)

            nightscoutAPI?.uploadTreatments(treatments)
                .receive(on: DispatchQueue.main)
                .sink { _ in self.showFeedback(message: "Site & App synchronisiert!") }
            receiveValue: { _ in }
                .store(in: &lifetime)
            changedAt = Date()
        }

        func logReservoirChange(with date: Date? = nil) {
            let finalDate = date ?? changedAt
            storage.save(finalDate, as: "monitor/reservoir.json")

            let treatment = NigtscoutTreatment(
                duration: nil, rawDuration: nil, rawRate: nil, absolute: nil, rate: nil,
                eventType: .nsInsulinChange,
                createdAt: finalDate,
                enteredBy: "iAPS",
                bolus: nil, insulin: nil, notes: "Reservoir Sync", carbs: nil, fat: nil, protein: nil,
                targetTop: nil, targetBottom: nil
            )

            let treatments: [NigtscoutTreatment] = [treatment]
            nightscoutAPI?.uploadTreatments(treatments)
                .receive(on: DispatchQueue.main)
                .sink { _ in self.showFeedback(message: "Insulin & App synchronisiert!") }
            receiveValue: { _ in }
                .store(in: &lifetime)

            changedAt = Date()
            detectedDiscrepancyDate = nil
        }

        func deleteLatestSiteChange() { deleteLatestTreatment(eventType: "Site Change", successMessage: "Site Change gelöscht") }
        func deleteLatestReservoirChange() {
            deleteLatestTreatment(eventType: "Insulin Change", successMessage: "Reservoir Change gelöscht") }

        private func deleteLatestTreatment(eventType: String, successMessage: String) {
            guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                  let url = URL(string: urlString),
                  let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey) else { return }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            if components.path.hasSuffix("/") { components.path.removeLast() }
            components.path.append("/api/v1/treatments.json")
            components.queryItems = [
                URLQueryItem(name: "find[eventType]", value: eventType),
                URLQueryItem(name: "count", value: "1")
            ]

            var request = URLRequest(url: components.url!)
            request.httpMethod = "DELETE"
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")

            URLSession.shared.dataTask(with: request) { _, response, _ in
                DispatchQueue.main.async {
                    // FIX: Nur ein Popup anzeigen, wenn auch ein Text übergeben wurde!
                    if !successMessage.isEmpty {
                        if let httpResponse = response as? HTTPURLResponse,
                           (200 ... 299).contains(httpResponse.statusCode)
                        {
                            self.showFeedback(message: successMessage)
                        }
                    }
                }
            }.resume()
        }

        // MARK: - Insulin Age Sync

        func syncInsulinAges() {
            isSyncingInsulinAge = true
            pumpInsulinAge = nil
            iapsInsulinAge = nil
            nightscoutInsulinAge = nil

            iapsInsulinAge = storage.retrieve("monitor/reservoir.json", as: Date.self) ?? storage
                .retrieve(OpenAPS.Monitor.podAge, as: Date.self)

            if let rawState = deviceManager.pumpManager?.rawState,
               let reservoirDateValue = rawState["reservoirDate"] as? Date
            {
                pumpInsulinAge = reservoirDateValue
            } else if let rawState = deviceManager.pumpManager?.rawState,
                      let reservoirDateInterval = rawState["reservoirDate"] as? TimeInterval
            {
                pumpInsulinAge = Date(timeIntervalSince1970: reservoirDateInterval)
            } else if let rawString = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: RawJSON.self),
                      let data = rawString.data(using: .utf8),
                      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            {
                let isoFormatter = ISO8601DateFormatter()
                pumpInsulinAge = array
                    .filter { ($0["_type"] as? String) == "Rewind" || ($0["_type"] as? String) == "Refill" }
                    .compactMap { $0["timestamp"] as? String }
                    .compactMap { str -> Date? in
                        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let d = isoFormatter.date(from: str) { return d }
                        isoFormatter.formatOptions = [.withInternetDateTime]
                        return isoFormatter.date(from: str)
                    }
                    .max()
            }

            fetchNightscoutInsulinAge { [weak self] date in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.nightscoutInsulinAge = date
                    self.isSyncingInsulinAge = false
                    self.evaluateInsulinAgeMismatch()
                }
            }
        }

        private func evaluateInsulinAgeMismatch() {
            let dates = [pumpInsulinAge, iapsInsulinAge, nightscoutInsulinAge].compactMap { $0 }
            guard dates.count >= 2 else {
                showFeedback(message: "Zu wenige Daten für Abgleich.")
                return
            }
            let minDate = dates.min()!
            let maxDate = dates.max()!
            if maxDate.timeIntervalSince(minDate) > 3600 {
                showInsulinAgeMismatch = true
            } else {
                showFeedback(message: "✓ Insulin Alter ist synchron!")
            }
        }

        private func fetchNightscoutInsulinAge(completion: @escaping (Date?) -> Void) {
            guard
                let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                let url = URL(string: urlString),
                let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
            else { completion(nil)
                return }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            if components.path.hasSuffix("/") { components.path.removeLast() }
            components.path.append("/api/v1/treatments.json")
            components.queryItems = [
                URLQueryItem(name: "find[eventType]", value: "Insulin Change"),
                URLQueryItem(name: "count", value: "1"),
                URLQueryItem(name: "sort$desc", value: "created_at")
            ]

            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                guard
                    let data = data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                    let first = json.first,
                    let createdAtStr = first["created_at"] as? String
                else { completion(nil)
                    return }

                let f1 = ISO8601DateFormatter()
                f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]

                for formatter in [f1, f2] {
                    if let date = formatter.date(from: createdAtStr) {
                        completion(date)
                        return
                    }
                }
                completion(nil)
            }.resume()
        }

        func applyInsulinAge(from source: InsulinAgeSource) {
            let chosenDate: Date?
            switch source {
            case .pump: chosenDate = pumpInsulinAge
            case .iaps: chosenDate = iapsInsulinAge
            case .nightscout: chosenDate = nightscoutInsulinAge
            }
            guard let date = chosenDate else { return }

            storage.save(date, as: "monitor/reservoir.json")
            deleteLatestTreatment(eventType: "Insulin Change", successMessage: "")

            let treatment = NigtscoutTreatment(
                duration: nil, rawDuration: nil, rawRate: nil, absolute: nil, rate: nil,
                eventType: .nsInsulinChange,
                createdAt: date,
                enteredBy: "iAPS",
                bolus: nil, insulin: nil, notes: "Reservoir Change (corrected)", carbs: nil, fat: nil, protein: nil,
                targetTop: nil, targetBottom: nil
            )

            nightscoutAPI?.uploadTreatments([treatment])
                .receive(on: DispatchQueue.main)
                .sink { _ in } receiveValue: { _ in }
                .store(in: &lifetime)

            writeDanaRefillEvent(date: date)
            showInsulinAgeMismatch = false
        }

        private func writeDanaRefillEvent(date: Date) {
            guard let refillPump = deviceManager.pumpManager as? RefillCapable else {
                showFeedback(message: "✓ App & NS synchron. (Dana: Bitte manuellen 0.5E Prime machen!)")
                return
            }
            refillPump.writeRefillEvent(date: date) { success in
                DispatchQueue.main.async {
                    self.showFeedback(
                        message: success
                            ? "✓ Dana Pumpe erfolgreich synchronisiert!"
                            : "Dana hat abgelehnt (Signalverlust?)"
                    )
                }
            }
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    nonisolated func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task { @MainActor in
            self.setupPump(nil)
        }
    }
}
