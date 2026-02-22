import Combine
import CommonCrypto
import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI
import UserNotifications

extension PumpConfig {
    enum ActionConfirmation: Int, Identifiable {
        case siteChange
        case reservoirChange
        var id: Int { rawValue }
    }

    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() var keychain: Keychain!
        @Injected() var storage: FileStorage!

        @Published var pumpSetupPresented: Bool = false
        @Published private(set) var pumpIdentifierToSetUp: String? = nil
        @Published private(set) var pumpManagerStatus: PumpManagerStatus? = nil
        @Published var changedAt = Date()
        @Published var confirmation: ActionConfirmation? = nil
        private(set) var initialSettings: PumpInitialSettings = .default
        @Published var alertNotAck: Bool = false

        var formattedChangedAt: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: changedAt)
        }

        override func subscribe() {
            alertNotAck = provider.initialAlertNotAck()
            provider.alertNotAck
                .receive(on: DispatchQueue.main)
                .assign(to: \.alertNotAck, on: self)
                .store(in: &lifetime)

            deviceManager.pumpManagerStatus
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpManagerStatus, on: self)
                .store(in: &lifetime)

            let basalSchedule = BasalRateSchedule(
                dailyItems: provider.basalProfile().map {
                    RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                }
            )
            let pumpSettings = provider.pumpSettings()
            initialSettings = PumpInitialSettings(
                maxBolusUnits: Double(pumpSettings.maxBolus),
                maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                basalSchedule: basalSchedule!
            )
        }

        func setupPump(_ identifier: String?) {
            pumpIdentifierToSetUp = identifier
            pumpSetupPresented = identifier != nil
        }

        func ack() {
            provider.deviceManager.alertHistoryStorage.forceNotification()
        }

        // MARK: - Site & Reservoir Change (Smooth Background Execution)

        func logSiteChange() {
            let dateToSave = changedAt
            let formattedDate = formattedChangedAt

            // Execute everything on a background thread to keep UI buttery smooth
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                // 1. Save locally for iAPS in the background
                self.storage.save(dateToSave, as: OpenAPS.Monitor.podAge)

                let semaphore = DispatchSemaphore(value: 0)

                // 2. Automatically delete the oldest entry
                self.deleteLatestTreatment(eventType: "Site Change") { _, _ in
                    semaphore.signal()
                }
                semaphore.wait()

                // 3. Give Nightscout DB time to settle (Winrace prevention)
                Thread.sleep(forTimeInterval: 2.0)

                // 4. Upload the new entry
                var uploadSuccess = false
                self.uploadRawTreatment(eventType: "Site Change", date: dateToSave) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                semaphore.wait()

                // 5. Fire acknowledged push notification
                DispatchQueue.main.async {
                    if uploadSuccess {
                        self.schedulePushNotification(
                            title: "Site / Pod Changed",
                            body: "Successfully updated to \(formattedDate)."
                        )
                    } else {
                        self.schedulePushNotification(title: "Upload Error", body: "Site Change could not be synchronized.")
                    }
                }
            }
            // Reset UI picker state smoothly on main thread
            changedAt = Date()
        }

        func logReservoirChange() {
            let dateToSave = changedAt
            let formattedDate = formattedChangedAt

            // Execute everything on a background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                // 1. Save locally for iAPS in the background
                self.storage.save(dateToSave, as: "monitor/reservoir.json")

                let semaphore = DispatchSemaphore(value: 0)

                // 2. Automatically delete the oldest entry
                self.deleteLatestTreatment(eventType: "Insulin Change") { _, _ in
                    semaphore.signal()
                }
                semaphore.wait()

                // 3. Prevent Race Condition
                Thread.sleep(forTimeInterval: 2.0)

                // 4. Upload the new entry
                var uploadSuccess = false
                self.uploadRawTreatment(eventType: "Insulin Change", date: dateToSave) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                semaphore.wait()

                // 5. Fire acknowledged push notification
                DispatchQueue.main.async {
                    if uploadSuccess {
                        self.schedulePushNotification(
                            title: "Reservoir Changed",
                            body: "Successfully updated to \(formattedDate)."
                        )
                    } else {
                        self.schedulePushNotification(title: "Upload Error", body: "Reservoir Change could not be synchronized.")
                    }
                }
            }
            changedAt = Date()
        }

        // MARK: - Direct Raw Upload & Delete Helper

        private func uploadRawTreatment(eventType: String, date: Date, completion: @escaping (Bool) -> Void) {
            guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                  let url = URL(string: urlString),
                  let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
            else {
                completion(false)
                return
            }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            if components.path.hasSuffix("/") { components.path.removeLast() }
            components.path.append("/api/v1/treatments.json")

            var queryItems = components.queryItems ?? []
            if secret.contains("-") {
                queryItems.append(URLQueryItem(name: "token", value: secret))
            }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let payload: [[String: Any]] = [[
                "eventType": eventType,
                "created_at": isoFormatter.string(from: date),
                "enteredBy": "Loop",
                "notes": eventType
            ]]

            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            URLSession.shared.dataTask(with: request) { _, response, _ in
                if let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) {
                    completion(true)
                } else {
                    completion(false)
                }
            }.resume()
        }

        private func deleteLatestTreatment(eventType: String, completion: @escaping (Bool, String?) -> Void) {
            guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                  let url = URL(string: urlString),
                  let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
            else {
                completion(false, "Missing credentials")
                return
            }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            if components.path.hasSuffix("/") { components.path.removeLast() }
            components.path.append("/api/v1/treatments.json")

            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "find[eventType]", value: eventType))
            queryItems.append(URLQueryItem(name: "count", value: "1"))
            if secret.contains("-") {
                queryItems.append(URLQueryItem(name: "token", value: secret))
            }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.httpMethod = "DELETE"
            request.timeoutInterval = 15
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")

            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    completion(false, error.localizedDescription)
                } else if let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) {
                    completion(true, nil)
                } else {
                    completion(false, "Server rejected deletion")
                }
            }.resume()
        }

        // MARK: - Push Notifications

        private func schedulePushNotification(title: String, body: String) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error sending push notification: \(error.localizedDescription)")
                }
            }
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task { @MainActor [weak self] in
            self?.setupPump(nil)
        }
    }
}

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
