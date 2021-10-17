//
//  BluetoothManager.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 10/1/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import CoreBluetooth
import Foundation
import os.log


protocol BluetoothManagerDelegate: AnyObject {

    /**
     Tells the delegate that the bluetooth manager has finished connecting to and discovering all required services of its peripheral, or that it failed to do so

     - parameter manager: The bluetooth manager
     - parameter peripheralManager: The peripheral manager
     - parameter error:   An error describing why bluetooth setup failed
     */
    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, isReadyWithError error: Error?)

    /**
     Asks the delegate whether the discovered or restored peripheral should be connected

     - parameter manager:    The bluetooth manager
     - parameter peripheral: The found peripheral

     - returns: True if the peripheral should connect
     */
    func bluetoothManager(_ manager: BluetoothManager, shouldConnectPeripheral peripheral: CBPeripheral) -> Bool

    /// Informs the delegate that the bluetooth manager received new data in the control characteristic
    ///
    /// - Parameters:
    ///   - manager: The bluetooth manager
    ///   - peripheralManager: The peripheral manager
    ///   - response: The data received on the control characteristic
    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, didReceiveControlResponse response: Data)

    /// Informs the delegate that the bluetooth manager received new data in the backfill characteristic
    ///
    /// - Parameters:
    ///   - manager: The bluetooth manager
    ///   - response: The data received on the backfill characteristic
    func bluetoothManager(_ manager: BluetoothManager, didReceiveBackfillResponse response: Data)

    /// Informs the delegate that the bluetooth manager received new data in the authentication characteristic
    ///
    /// - Parameters:
    ///   - manager: The bluetooth manager
    ///   - peripheralManager: The peripheral manager
    ///   - response: The data received on the authentication characteristic
    func bluetoothManager(_ manager: BluetoothManager, peripheralManager: PeripheralManager, didReceiveAuthenticationResponse response: Data)
}


class BluetoothManager: NSObject {

    var stayConnected: Bool {
        get {
            return lockedStayConnected.value
        }
        set {
            lockedStayConnected.value = newValue
        }
    }
    private let lockedStayConnected: Locked<Bool> = Locked(true)

    weak var delegate: BluetoothManagerDelegate?

    private let log = OSLog(category: "BluetoothManager")

    /// Isolated to `managerQueue`
    private var manager: CBCentralManager! = nil

    /// Isolated to `managerQueue`
    private var peripheral: CBPeripheral? {
        get {
            return peripheralManager?.peripheral
        }
        set {
            guard let peripheral = newValue else {
                peripheralManager = nil
                return
            }

            if let peripheralManager = peripheralManager {
                peripheralManager.peripheral = peripheral
            } else {
                peripheralManager = PeripheralManager(
                    peripheral: peripheral,
                    configuration: .dexcomG5,
                    centralManager: manager
                )
            }
        }
    }

    var peripheralIdentifier: UUID? {
        get {
            return lockedPeripheralIdentifier.value
        }
        set {
            lockedPeripheralIdentifier.value = newValue
        }
    }
    private let lockedPeripheralIdentifier: Locked<UUID?> = Locked(nil)

    /// Isolated to `managerQueue`
    private var peripheralManager: PeripheralManager? {
        didSet {
            oldValue?.delegate = nil
            peripheralManager?.delegate = self

            peripheralIdentifier = peripheralManager?.peripheral.identifier
        }
    }

    // MARK: - Synchronization

    private let managerQueue = DispatchQueue(label: "com.loudnate.CGMBLEKit.bluetoothManagerQueue", qos: .unspecified)

    override init() {
        super.init()

        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.loudnate.CGMBLEKit"])
        }
    }

    // MARK: - Actions

    func scanForPeripheral() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))

        managerQueue.sync {
            self.managerQueue_scanForPeripheral()
        }
    }

    func disconnect() {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))

        managerQueue.sync {
            if manager.isScanning {
                manager.stopScan()
            }

            if let peripheral = peripheral {
                manager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    private func managerQueue_scanForPeripheral() {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        guard manager.state == .poweredOn else {
            return
        }

        let currentState = peripheral?.state ?? .disconnected
        guard currentState != .connected else {
            return
        }

        if let peripheralID = peripheralIdentifier, let peripheral = manager.retrievePeripherals(withIdentifiers: [peripheralID]).first {
            log.debug("Re-connecting to known peripheral %{public}@", peripheral.identifier.uuidString)
            self.peripheral = peripheral
            self.manager.connect(peripheral)
        } else if let peripheral = manager.retrieveConnectedPeripherals(withServices: [
                TransmitterServiceUUID.advertisement.cbUUID,
                TransmitterServiceUUID.cgmService.cbUUID
            ]).first,
            delegate == nil || delegate!.bluetoothManager(self, shouldConnectPeripheral: peripheral)
        {
            log.debug("Found system-connected peripheral: %{public}@", peripheral.identifier.uuidString)
            self.peripheral = peripheral
            self.manager.connect(peripheral)
        } else {
            log.debug("Scanning for peripherals")
            manager.scanForPeripherals(withServices: [
                    TransmitterServiceUUID.advertisement.cbUUID
                ],
                options: nil
            )
        }
    }

    /**
    
     Persistent connections don't seem to work with the transmitter shutoff: The OS won't re-wake the
     app unless it's scanning.
     
     The sleep gives the transmitter time to shut down, but keeps the app running.

     */
    fileprivate func scanAfterDelay() {
        DispatchQueue.global(qos: .utility).async {
            Thread.sleep(forTimeInterval: 2)

            self.scanForPeripheral()
        }
    }

    // MARK: - Accessors

    var isScanning: Bool {
        dispatchPrecondition(condition: .notOnQueue(managerQueue))

        var isScanning = false
        managerQueue.sync {
            isScanning = manager.isScanning
        }
        return isScanning
    }

    override var debugDescription: String {
        return [
            "## BluetoothManager",
            peripheralManager.map(String.init(reflecting:)) ?? "No peripheral",
        ].joined(separator: "\n")
    }
}


extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        peripheralManager?.centralManagerDidUpdateState(central)
        log.default("%{public}@: %{public}@", #function, String(describing: central.state.rawValue))

        switch central.state {
        case .poweredOn:
            managerQueue_scanForPeripheral()
        case .resetting, .poweredOff, .unauthorized, .unknown, .unsupported:
            fallthrough
        @unknown default:
            if central.isScanning {
                central.stopScan()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                if delegate == nil || delegate!.bluetoothManager(self, shouldConnectPeripheral: peripheral) {
                    log.default("Restoring peripheral from state: %{public}@", peripheral.identifier.uuidString)
                    self.peripheral = peripheral
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        log.info("%{public}@: %{public}@", #function, peripheral)
        if delegate == nil || delegate!.bluetoothManager(self, shouldConnectPeripheral: peripheral) {
            self.peripheral = peripheral

            central.connect(peripheral, options: nil)

            central.stopScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        log.default("%{public}@: %{public}@", #function, peripheral)
        if central.isScanning {
            central.stopScan()
        }

        peripheralManager?.centralManager(central, didConnect: peripheral)

        if case .poweredOn = manager.state, case .connected = peripheral.state, let peripheralManager = peripheralManager {
            self.delegate?.bluetoothManager(self, peripheralManager: peripheralManager, isReadyWithError: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        log.default("%{public}@: %{public}@", #function, peripheral)
        // Ignore errors indicating the peripheral disconnected remotely, as that's expected behavior
        if let error = error as NSError?, CBError(_nsError: error).code != .peripheralDisconnected {
            log.error("%{public}@: %{public}@", #function, error)
            if let peripheralManager = peripheralManager {
                self.delegate?.bluetoothManager(self, peripheralManager: peripheralManager, isReadyWithError: error)
            }
        }

        if stayConnected {
            scanAfterDelay()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(managerQueue))

        log.error("%{public}@: %{public}@", #function, String(describing: error))
        if let error = error, let peripheralManager = peripheralManager {
            self.delegate?.bluetoothManager(self, peripheralManager: peripheralManager, isReadyWithError: error)
        }

        if stayConnected {
            scanAfterDelay()
        }
    }
}


extension BluetoothManager: PeripheralManagerDelegate {
    func peripheralManager(_ manager: PeripheralManager, didReadRSSI RSSI: NSNumber, error: Error?) {
        
    }

    func peripheralManagerDidUpdateName(_ manager: PeripheralManager) {

    }

    func completeConfiguration(for manager: PeripheralManager) throws {

    }

    func peripheralManager(_ manager: PeripheralManager, didUpdateValueFor characteristic: CBCharacteristic) {
        guard let value = characteristic.value else {
            return
        }

        switch CGMServiceCharacteristicUUID(rawValue: characteristic.uuid.uuidString.uppercased()) {
        case .none, .communication?:
            return
        case .control?:
            self.delegate?.bluetoothManager(self, peripheralManager: manager, didReceiveControlResponse: value)
        case .backfill?:
            self.delegate?.bluetoothManager(self, didReceiveBackfillResponse: value)
        case .authentication?:
            self.delegate?.bluetoothManager(self, peripheralManager: manager, didReceiveAuthenticationResponse: value)
        }
    }
}
