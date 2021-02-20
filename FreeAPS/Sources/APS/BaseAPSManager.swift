import Combine
import LoopKit
import MinimedKit
import RileyLinkBLEKit
import RileyLinkKit
import Swinject

final class BaseAPSManager: APSManager, Injectable {
    private var openAPS: OpenAPS!
    @Injected() var deviceDataManager: DeviceDataManager!

    let rileyDisplayStates = CurrentValueSubject<[RileyDisplayState], Never>([])

    private(set) var devices: [RileyLinkDevice] = [] {
        didSet {
            print("Devices: \(devices)")
            updateDisplayStates()
        }
    }

    private var deviceRSSI: [UUID: Int] = [:] {
        didSet {
            print("RSSI: \(deviceRSSI)")
            updateDisplayStates()
        }
    }

    private(set) var rileyLinkPumpManager: RileyLinkPumpManager!

    private var rssiFetchTimer: Timer? {
        willSet {
            rssiFetchTimer?.invalidate()
        }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: resolver.resolve(FileStorage.self)!)
        rileyLinkPumpManager = RileyLinkPumpManager(
            rileyLinkDeviceProvider: deviceDataManager.rileyLinkConnectionManager.deviceProvider,
            rileyLinkConnectionManager: deviceDataManager.rileyLinkConnectionManager
        )
        registerNotifications()
        reloadDevices()
        rssiFetchTimer = Timer.scheduledTimer(
            timeInterval: 3,
            target: self,
            selector: #selector(updateRSSI),
            userInfo: nil,
            repeats: true
        )
        updateRSSI()
    }

    private func updateDisplayStates() {
        rileyDisplayStates.value = devices.map {
            RileyDisplayState(
                id: $0.peripheralIdentifier,
                name: $0.name ?? "unknown",
                rssi: self.deviceRSSI[$0.peripheralIdentifier],
                connected: false
            )
        }
    }

    private func registerNotifications() {
        // Register for manager notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadDevices),
            name: .ManagerDevicesDidChange,
            object: rileyLinkPumpManager.rileyLinkDeviceProvider
        )

        // Register for device notifications
        for name in [.DeviceConnectionStateDidChange, .DeviceRSSIDidChange, .DeviceNameDidChange] as [Notification.Name] {
            NotificationCenter.default.addObserver(self, selector: #selector(deviceDidUpdate(_:)), name: name, object: nil)
        }
    }

    @objc private func reloadDevices() {
        rileyLinkPumpManager.rileyLinkDeviceProvider.getDevices { devices in
            DispatchQueue.main.async { [weak self] in
                self?.devices = devices
                devices.forEach { self?.rileyLinkPumpManager.connectToRileyLink($0) }
            }
        }
    }

    @objc private func deviceDidUpdate(_ note: Notification) {
        DispatchQueue.main.async {
            if let device = note.object as? RileyLinkDevice {
                if let rssi = note.userInfo?[RileyLinkDevice.notificationRSSIKey] as? Int {
                    self.deviceRSSI[device.peripheralIdentifier] = rssi
                }
            }
        }
    }

    @objc public func updateRSSI() {
        for device in devices {
            device.readRSSI()
        }
    }

    func runTest() {
        openAPS.test()
    }
}
