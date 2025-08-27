import Foundation
import Swinject

protocol RemoteNotificationsManager {
    func setDeviceToken(_ deviceToken: String)
    func subscribe() async -> String?
    func unsubscribe() async -> String?
}

final class BaseRemoteNotificationsManager: NSObject, RemoteNotificationsManager, Injectable, SettingsObserver {
    private let keychain: Keychain
    private let settingsManager: SettingsManager
    private let broadcaster: Broadcaster

    private let service = NetworkService()

    private var deviceToken: String?
    private var nightscountHeartbeatServiceEnabled: Bool = false
    private var nightscountHeartbeatServiceURL: String?
    private var cgm: CGMType?

    private let bundleId = Bundle.main.bundleIdentifier

    init(resolver: Resolver) {
        keychain = resolver.resolve(Keychain.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        broadcaster = resolver.resolve(Broadcaster.self)!

        super.init()

        nightscountHeartbeatServiceEnabled = settingsManager.settings.nightscountHeartbeatServiceEnabled
        nightscountHeartbeatServiceURL = settingsManager.settings.nightscountHeartbeatServiceURL
        cgm = settingsManager.settings.cgm
        broadcaster.register(SettingsObserver.self, observer: self)
        refresh()
    }

    func setDeviceToken(_ deviceToken: String) {
        guard self.deviceToken == nil else { return }
        self.deviceToken = deviceToken
        refresh()
    }

    func subscribe() async -> String? {
        guard !nightscountHeartbeatServiceEnabled else { return nil }
        return await callSubscribeEnpoint()
    }

    func unsubscribe() async -> String? {
        guard nightscountHeartbeatServiceEnabled else { return nil }
        return await callUnsubscribeEnpoint()
    }

    func settingsDidChange(_: FreeAPSSettings) {
        if nightscountHeartbeatServiceEnabled != settingsManager.settings.nightscountHeartbeatServiceEnabled ||
            nightscountHeartbeatServiceURL != settingsManager.settings.nightscountHeartbeatServiceURL ||
            cgm != settingsManager.settings.cgm
        {
            nightscountHeartbeatServiceEnabled = settingsManager.settings.nightscountHeartbeatServiceEnabled
            nightscountHeartbeatServiceURL = settingsManager.settings.nightscountHeartbeatServiceURL
            cgm = settingsManager.settings.cgm
            refresh()
        }
    }

    private func refresh() {
        // do nothing until we get the device token
        guard deviceToken != nil else { return }
        if cgm == .nightscout {
            if nightscountHeartbeatServiceURL != nil,
               nightscountHeartbeatServiceEnabled
            {
                print("CGM is nightscout, heartbeat enabled, (re)subscribing to Nightscout heartbeat service")
                Task {
                    await callSubscribeEnpoint()
                }
            }
        } else {
            if nightscountHeartbeatServiceEnabled {
                print(
                    "CGM changed from nightscout to something else, heartbeat enabled, unsubscribing from Nightscout heartbeat service"
                )
                Task {
                    await callUnsubscribeEnpoint()
                    // TODO: this change doesn't propagate to the CGM view unless it's closed and reopened
                    settingsManager.settings.nightscountHeartbeatServiceEnabled = false
                }
            }
        }
    }

    private func makePayload() -> SubscribeRequest? {
        guard let bundleId = self.bundleId,
              let deviceToken = self.deviceToken,
              let nightscoutURL = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let nightscoutSecret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey),
              nightscoutURL != "",
              nightscoutSecret != ""
        else { return nil }

        #if DEBUG
            let useSandbox = true
        #else
            let useSandbox = false
        #endif

        return SubscribeRequest(
            deviceToken: deviceToken,
            nsBase: nightscoutURL,
            apiSecretSha1: nightscoutSecret.sha1(),
            bundleId: bundleId,
            useSandbox: useSandbox
        )
    }

    private func callSubscribeEnpoint() async -> String? {
        guard let urlString = nightscountHeartbeatServiceURL,
              let url = URL(string: urlString),
              let payload = makePayload()
        else { return "Missing settings" }

        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/api/v1/ns/subscribe"

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
//        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(payload)
        request.httpMethod = "POST"

        do {
            let response = try await service.decode(SubscribeResponse.self, from: request)
            if response.okay { return nil }
            return response.error ?? "Failed to subscribe."
        } catch {
            warning(.service, "failed to subscribe to nightscout heartbeat service: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    private func callUnsubscribeEnpoint() async -> String? {
        guard let urlString = nightscountHeartbeatServiceURL,
              let url = URL(string: urlString),
              let payload = makePayload()
        else { return "Missing settings" }

        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/api/v1/ns/unsubscribe"

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
//        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try! JSONCoding.encoder.encode(payload)
        request.httpMethod = "POST"

        do {
            let response = try await service.decode(SubscribeResponse.self, from: request)
            if response.okay { return nil }
            return response.error ?? "Failed to subscribe."
        } catch {
            warning(.service, "failed to unsubscribe from nightscout heartbeat service: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}

private extension BaseRemoteNotificationsManager {
    struct SubscribeRequest: Codable {
        let deviceToken: String
        let nsBase: String
        let apiSecretSha1: String
        let bundleId: String
        let useSandbox: Bool
    }

    struct SubscribeResponse: Codable {
        let okay: Bool
        let error: String?
    }
}
