import Combine
import Foundation
import HealthKit
import LibreTransmitter
import LoopKit
import LoopKitUI
import Swinject

public class AppGroupCGM: CGMManager, AppGroupCGMHeartBeatDelegate {
    public static let pluginIdentifier = "AppGroupCGM"

    public static let localizedTitle = NSLocalizedString(
        "Shared App Group CGM",
        comment: "Title for the Shared App Group CGM option"
    )

    public var localizedTitle: String {
        AppGroupCGM.localizedTitle
    }

    public var glucoseDisplay: GlucoseDisplayable? { nil }

    public var cgmManagerStatus: CGMManagerStatus {
        .init(hasValidSensorSession: isOnboarded, device: nil)
    }

    public var isOnboarded: Bool {
        true
    }

    public let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    public var delegateQueue: DispatchQueue! {
        get { delegate.queue }
        set { delegate.queue = newValue }
    }

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get { delegate.delegate }
        set { delegate.delegate = newValue }
    }

    public var providesBLEHeartbeat: Bool {
        appGroupSource.deviceAddress != nil
    }

    public var managedDataInterval: TimeInterval?

    public var shouldSyncToRemoteService = false

    private let processQueue = DispatchQueue(label: "AppGroupCGM.processQueue")

    private let lockedState: Locked<AppGroupCGMState>

    public var state: AppGroupCGMState {
        lockedState.value
    }

    let appGroupSource = AppGroupSource()

    public init() {
        lockedState = Locked(AppGroupCGMState())
        updateTimer = DispatchTimer(timeInterval: 10, queue: processQueue)
        scheduleUpdateTimer()
    }

    public required init?(rawState: RawStateValue) {
        lockedState = Locked(AppGroupCGMState(rawValue: rawState))
        updateTimer = DispatchTimer(timeInterval: 10, queue: processQueue)
        scheduleUpdateTimer()
    }

    public var rawState: RawStateValue {
        state.rawValue
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        completion(appGroupSource.fetch())
    }

    public var debugDescription: String {
        "## SharedAppGroupCGM\n"
    }

    public var appURL: URL? {
        appGroupSource.latestReadingFrom?.appURL
    }

    private let updateTimer: DispatchTimer

    private func scheduleUpdateTimer() {
        updateTimer.suspend()
        updateTimer.eventHandler = { [weak self] in
            guard let self = self else { return }
            self.fetchNewDataIfNeeded { result in
                guard case .newData = result else { return }
                self.delegate.notify { delegate in
                    delegate?.cgmManager(self, hasNew: result)
                }
            }
        }
        updateTimer.resume()
        updateTimer.fire()
    }

    func heartbeat() {
        updateTimer.fire()
    }
}

// MARK: - AlertResponder implementation

public extension AppGroupCGM {
    func acknowledgeAlert(alertIdentifier _: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}

// MARK: - AlertSoundVendor implementation

public extension AppGroupCGM {
    func getSoundBaseURL() -> URL? { nil }
    func getSounds() -> [Alert.Sound] { [] }
}

// ----------------------------------------

public struct AppGroupCGMState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    init() {}

    public init(rawValue _: RawValue) {}

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        return rawValue
    }
}
