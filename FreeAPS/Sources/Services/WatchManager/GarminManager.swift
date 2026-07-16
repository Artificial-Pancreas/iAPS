import Combine
@preconcurrency import ConnectIQ
import Foundation
import Swinject

@MainActor protocol GarminManager: Sendable {
    func selectDevices() async -> [CodableDevice]
    func updateListDevices(devices: [CodableDevice])
    var devices: [CodableDevice] { get }
    func sendState(_ data: Data)

    var stateRequest: (@Sendable() async -> Data)? { get }
    func setStateRequest(_ req: (@Sendable() async -> Data)?)
}

extension Notification.Name {
    static let openFromGarminConnect = Notification.Name("Notification.Name.openFromGarminConnect")
}

@MainActor
final class BaseGarminManager: NSObject, GarminManager {
    private enum Config {
        static let watchfaceUUID = UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")
        static let watchdataUUID = UUID(uuidString: "71CF0982-CA41-42A5-8441-EA81D36056C3")
    }

    private let connectIQ = ConnectIQ.sharedInstance()

    private let appCoordinator: AppCoordinator

    private let notificationCenter: NotificationCenter

    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [CodableDevice] = []

    private var watchfaces: [IQApp] = []

    private(set) var stateRequest: (@Sendable() async -> Data)?

    func setStateRequest(_ req: (@Sendable() async -> Data)?) {
        stateRequest = req
    }

    private let stateSubject = PassthroughSubject<NSDictionary, Never>()

    private var devicesRaw: [IQDevice] = [] {
        didSet {
            persistedDevices = devicesRaw.map(CodableDevice.init)
            watchfaces = []
            devicesRaw.forEach { device in
                connectIQ?.register(forDeviceEvents: device, delegate: self)
                let watchfaceApp = IQApp(
                    uuid: Config.watchfaceUUID,
                    store: UUID(),
                    device: device
                )
                let watchDataFieldApp = IQApp(
                    uuid: Config.watchdataUUID,
                    store: UUID(),
                    device: device
                )
                watchfaces.append(watchfaceApp!)
                watchfaces.append(watchDataFieldApp!)
                connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
            }
        }
    }

    var devices: [CodableDevice] {
        persistedDevices
    }

    private let lifetime = Lifetime()

    private var selectContinuation: CheckedContinuation<[CodableDevice], Never>?
    private var selectTimeoutTask: Task<Void, Never>?

    init(
        notificationCenter: NotificationCenter,
        appCoordinator: AppCoordinator
    ) {
        self.notificationCenter = notificationCenter
        self.appCoordinator = appCoordinator
        super.init()

        connectIQ?.initialize(withUrlScheme: "freeaps-x", uiOverrideDelegate: self)

        restoreDevices()

        subscribeToOpenFromGarminConnect()
        setupApplications()
        subscribeState()
    }

    private func restoreDevices() {
        devicesRaw = persistedDevices.map(\.iqDevice)
    }

    private func subscribeToOpenFromGarminConnect() {
        notificationCenter
            .publisher(for: .openFromGarminConnect)
            .sink { notification in
                guard let url = notification.object as? URL else { return }
                self.parseDevicesFor(url: url)
            }
            .store(in: lifetime)
    }

    private func subscribeState() {
        func sendToWatchface(state: NSDictionary) {
            let connectIQ = self.connectIQ
            // NSDictionary is non-Sendable Foundation type;
            // if ConnectIQ delivers these callbacks on main and doesn't share `state` concurrently, capturing it into the @Sendable callback is safe.
            nonisolated(unsafe) let state = state
            watchfaces.forEach { app in
                connectIQ?.getAppStatus(app) { status in
                    guard status?.isInstalled ?? false else {
                        debug(.service, "Garmin: watchface app not installed")
                        return
                    }
                    debug(.service, "Garmin: sending message to watchface")

                    connectIQ?.sendMessage(state, to: app, progress: { _, _ in
                        // debug(.service, "Garmin: sending progress: \(Int(Double(sent) / Double(all) * 100)) %")
                    }, completion: { result in
                        if result == .success {
                            debug(.service, "Garmin: message sent")
                        } else {
                            debug(.service, "Garmin: message failed")
                        }
                    })
                }
            }
        }

        stateSubject
            .throttle(for: .seconds(10), scheduler: DispatchQueue.main, latest: true)
            .sink { state in
                sendToWatchface(state: state)
            }
            .store(in: lifetime)
    }

    private func parseDevicesFor(url: URL) {
        let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice] ?? []
        devicesRaw = parsed
        finishSelection(with: parsed.map(CodableDevice.init))
    }

    private func setupApplications() {
        devices.forEach { _ in
        }
    }

    func selectDevices() async -> [CodableDevice] {
        let selected: [CodableDevice] = await withCheckedContinuation { continuation in
            // abandon any in-flight selection
            finishSelection(with: [])

            selectContinuation = continuation
            connectIQ?.showDeviceSelection()

            // replaces .timeout(120).replaceEmpty(with: [])
            selectTimeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                finishSelection(with: [])
            }
        }
        return selected // .map(\.iqDevice)
    }

    private func finishSelection(with result: [CodableDevice]) {
        selectTimeoutTask?.cancel()
        selectTimeoutTask = nil
        selectContinuation?.resume(returning: result)
        selectContinuation = nil
    }

    func updateListDevices(devices: [CodableDevice]) {
        devicesRaw = devices.map(\.iqDevice)
    }

    func sendState(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary else {
            return
        }
        stateSubject.send(object)
    }
}

extension BaseGarminManager: IQUIOverrideDelegate {
    nonisolated func needsToInstallConnectMobile() {
        debug(.apsManager, NSLocalizedString("Garmin is not available", comment: ""))
        Task { @MainActor in
            let messageCont = MessageContent(
                content: NSLocalizedString(
                    "The app Garmin Connect must be installed to use for iAPS.\n Go to App Store to download it",
                    comment: ""
                ),
                type: .warning
            )
            appCoordinator.sendAlertMessage(messageCont)
        }
    }
}

extension BaseGarminManager: IQDeviceEventDelegate {
    nonisolated func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        let uuidForLog = String(describing: device.uuid)
        Task { @MainActor in
            switch status {
            case .invalidDevice:
                debug(.service, "Garmin: invalidDevice, Device: \(uuidForLog)")
            case .bluetoothNotReady:
                debug(.service, "Garmin: bluetoothNotReady, Device: \(uuidForLog)")
            case .notFound:
                debug(.service, "Garmin: notFound, Device: \(uuidForLog)")
            case .notConnected:
                debug(.service, "Garmin: notConnected, Device: \(uuidForLog)")
            case .connected:
                debug(.service, "Garmin: connected, Device: \(uuidForLog)")
            @unknown default:
                debug(.service, "Garmin: unknown state, Device: \(uuidForLog)")
            }
        }
    }
}

extension BaseGarminManager: IQAppMessageDelegate {
    nonisolated func receivedMessage(_ message: Any, from app: IQApp) {
        debug(.service, "got message: \(message) from app: \(app.uuid!)")
        if message as? String == "status" {
            Task { @MainActor in
                if let watchState = await stateRequest?() {
                    sendState(watchState)
                }
            }
        }
    }
}

struct CodableDevice: Codable, Equatable {
    let id: UUID
    let modelName: String
    let friendlyName: String

    init(iqDevice: IQDevice) {
        id = iqDevice.uuid
        modelName = iqDevice.modelName
        friendlyName = iqDevice.modelName
    }

    var iqDevice: IQDevice {
        IQDevice(id: id, modelName: modelName, friendlyName: friendlyName)
    }
}
