import CoreBluetooth
import LoopKit
import LoopKitUI

protocol BluetoothStateManager: BluetoothProvider, Sendable {}

// @unchecked Sendable - needed because we have mutable state here;
// access to the mutable state is gated with a lock, so our promise to be Sendable is honest
public final class BaseBluetoothStateManager: NSObject, BluetoothStateManager, @unchecked Sendable {
    private let lock = NSLock()
    private var _completion: ((BluetoothAuthorization) -> Void)?
    private var _centralManager: CBCentralManager?
    private let bluetoothObservers = WeakSynchronizedSet<BluetoothObserver>()

    override init() {
        super.init()
        if bluetoothAuthorization != .notDetermined {
            let centralManager = CBCentralManager(delegate: self, queue: nil)
            lock.withLock { _centralManager = centralManager }
        }
    }

    public var bluetoothAuthorization: BluetoothAuthorization {
        BluetoothAuthorization(CBCentralManager.authorization)
    }

    public var bluetoothState: BluetoothState {
        let centralManager = lock.withLock { _centralManager }
        guard let centralManager else {
            return .unknown
        }
        return BluetoothState(centralManager.state)
    }

    public func authorizeBluetooth(_ completion: @escaping (BluetoothAuthorization) -> Void) {
        guard lock.withLock({ _centralManager }) == nil else {
            completion(bluetoothAuthorization)
            return
        }
        let central = CBCentralManager(delegate: self, queue: nil)
        lock.withLock { _completion = completion
            _centralManager = central }
    }

    public func addBluetoothObserver(_ observer: BluetoothObserver, queue: DispatchQueue = .main) {
        bluetoothObservers.insert(observer, queue: queue)
    }

    public func removeBluetoothObserver(_ observer: BluetoothObserver) {
        bluetoothObservers.removeElement(observer)
    }
}

// MARK: - CBCentralManagerDelegate

extension BaseBluetoothStateManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let completion = lock.withLock { let c = _completion
            _completion = nil
            return c }
        completion?(bluetoothAuthorization)
        bluetoothObservers.forEach { $0.bluetoothDidUpdateState(BluetoothState(central.state)) }
    }
}

// MARK: - BluetoothAuthorization

private extension BluetoothAuthorization {
    init(_ authorization: CBManagerAuthorization) {
        switch authorization {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .allowedAlways:
            self = .authorized
        @unknown default:
            self = .notDetermined
        }
    }
}

// MARK: - BluetoothState

private extension BluetoothState {
    init(_ state: CBManagerState) {
        switch state {
        case .unknown:
            self = .unknown
        case .resetting:
            self = .resetting
        case .unsupported:
            #if IOS_SIMULATOR
                self = .poweredOn // Simulator reports unsupported, but pretend it is powered on
            #else
                self = .unsupported
            #endif
        case .unauthorized:
            self = .unauthorized
        case .poweredOff:
            self = .poweredOff
        case .poweredOn:
            self = .poweredOn
        @unknown default:
            self = .unknown
        }
    }
}
