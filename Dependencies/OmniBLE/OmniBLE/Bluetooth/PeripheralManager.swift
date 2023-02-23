//
//  PeripheralManager.swift
//  xDripG5
//  OmniBLE
//
//  Based on CGMBLEKit/CGMBLEKit/PeripheralManager.swift
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import Foundation
import os.log

class PeripheralManager: NSObject {

    // TODO: Make private
    let log = OSLog(category: "DashPeripheralManager")

    ///
    /// This is mutable, because CBPeripheral instances can seemingly become invalid, and need to be periodically re-fetched from CBCentralManager
    var peripheral: CBPeripheral {
        didSet {
            guard oldValue !== peripheral else {
                return
            }

            log.error("Replacing peripheral reference %{public}@ -> %{public}@", oldValue, peripheral)

            oldValue.delegate = nil
            peripheral.delegate = self

            queue.sync {
                self.needsConfiguration = true
            }
        }
    }

    var dataQueue: [Data] = []
    var cmdQueue: [Data] = []
    let queueLock = NSCondition()

    var idleStart: Date? = nil

    var needsReconnection: Bool {
        guard let start = idleStart else { return false }

        return Date().timeIntervalSince(start) > .minutes(2.9)
    }


    /// The dispatch queue used to serialize operations on the peripheral
    let queue = DispatchQueue(label: "com.loopkit.PeripheralManager.queue", qos: .unspecified)

    private let sessionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.OmniBLE.OmnipodDevice.sessionQueue"
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    /// The condition used to signal command completion
    let commandLock = NSCondition()

    /// The required conditions for the operation to complete
    private var commandConditions = [CommandCondition]()

    /// Any error surfaced during the active operation
    private var commandError: Error?

    private(set) weak var central: CBCentralManager?

    let configuration: Configuration

    // Confined to `queue`
    private var needsConfiguration = true

    weak var delegate: PeripheralManagerDelegate?

    init(peripheral: CBPeripheral, configuration: Configuration, centralManager: CBCentralManager) {
        self.peripheral = peripheral
        self.central = centralManager
        self.configuration = configuration

        super.init()

        peripheral.delegate = self

        assertConfiguration()
    }
}


// MARK: - Nested types
extension PeripheralManager {
    struct Configuration {
        var serviceCharacteristics: [CBUUID: [CBUUID]] = [:]
        var notifyingCharacteristics: [CBUUID: [CBUUID]] = [:]
        var valueUpdateMacros: [CBUUID: (_ manager: PeripheralManager) -> Void] = [:]
    }

    enum CommandCondition {
        case notificationStateUpdate(characteristicUUID: CBUUID, enabled: Bool)
        case valueUpdate(characteristic: CBCharacteristic, matching: ((Data?) -> Bool)?)
        case write(characteristic: CBCharacteristic)
        case discoverServices
        case discoverCharacteristicsForService(serviceUUID: CBUUID)
        case connect
    }
}

protocol PeripheralManagerDelegate: AnyObject {
    // Called from the PeripheralManager's queue
    func completeConfiguration(for manager: PeripheralManager) throws
}


// MARK: - Operation sequence management
extension PeripheralManager {


    func configureAndRun(_ block: @escaping (_ manager: PeripheralManager) -> Void) -> (() -> Void) {
        return {
            if self.needsReconnection {
                self.log.default("Triggering forceful reconnect")
                do {
                    try self.reconnect(timeout: 5)
                } catch let error {
                    self.log.error("Error while forcing reconnection: %{public}@", String(describing: error))
                }
            }

            if !self.needsConfiguration && self.peripheral.services == nil {
                self.log.error("Configured peripheral has no services. Reconfiguring %{public}@", self.peripheral)
            }

            if self.needsConfiguration || self.peripheral.services == nil {
                do {
                    self.log.default("Applying configuration")
                    try self.applyConfiguration()
                    self.needsConfiguration = false

                    if let delegate = self.delegate {
                        try delegate.completeConfiguration(for: self)
                        
                        self.log.default("Delegate configuration notified")
                    }

                    self.log.default("Peripheral configuration completed")
                } catch let error {
                    self.log.error("Error applying peripheral configuration: %{public}@", String(describing: error))
                    // Will retry
                }
            }

            block(self)
        }
    }

    func perform(_ block: @escaping (_ manager: PeripheralManager) -> Void) {
        queue.async(execute: configureAndRun(block))
    }

    func assertConfiguration() {
        if peripheral.state == .connected && central?.state == .poweredOn {
            perform { (_) in
                // Intentionally empty to trigger configuration if necessary
            }
        }
    }

    private func applyConfiguration(discoveryTimeout: TimeInterval = 2) throws {
        try discoverServices(configuration.serviceCharacteristics.keys.map { $0 }, timeout: discoveryTimeout)

        for service in peripheral.services ?? [] {
            log.default("Discovered service: %{public}@", service)
            guard let characteristics = configuration.serviceCharacteristics[service.uuid] else {
                // Not all services may have characteristics
                continue
            }
            try discoverCharacteristics(characteristics, for: service, timeout: discoveryTimeout)
        }

        for (serviceUUID, characteristicUUIDs) in configuration.notifyingCharacteristics {
            guard let service = peripheral.services?.itemWithUUID(serviceUUID) else {
                throw PeripheralManagerError.unknownCharacteristic
            }

            for characteristicUUID in characteristicUUIDs {
                guard let characteristic = service.characteristics?.itemWithUUID(characteristicUUID) else {
                    throw PeripheralManagerError.unknownCharacteristic
                }

                guard !characteristic.isNotifying else {
                    continue
                }

                try setNotifyValue(true, for: characteristic, timeout: discoveryTimeout)
            }
        }
    }
}


// MARK: - Synchronous Commands
extension PeripheralManager {
    /// - Throws: PeripheralManagerError
    func runCommand(timeout: TimeInterval, command: () -> Void) throws {
        // Prelude
        dispatchPrecondition(condition: .onQueue(queue))
        guard central?.state == .poweredOn && peripheral.state == .connected else {
            self.log.info("runCommand guard failed - bluetooth not running or peripheral not connected: peripheral %@", peripheral)
            throw PeripheralManagerError.notReady
        }

        commandLock.lock()

        defer {
            commandLock.unlock()
        }

        guard commandConditions.isEmpty else {
            throw PeripheralManagerError.emptyValue
        }

        // Run
        command()

        guard !commandConditions.isEmpty else {
            // If the command didn't add any conditions, then finish immediately
            return
        }

        // Postlude
        let signaled = commandLock.wait(until: Date(timeIntervalSinceNow: timeout))

        defer {
            commandError = nil
            commandConditions = []
        }

        guard signaled else {
            self.log.info("runCommand lock timeout reached - not signalled")
            throw PeripheralManagerError.timeout(commandConditions)
        }

        if let error = commandError {
            throw PeripheralManagerError.cbPeripheralError(error)
        }
    }

    /// It's illegal to call this without first acquiring the commandLock
    ///
    /// - Parameter condition: The condition to add
    func addCondition(_ condition: CommandCondition) {
        dispatchPrecondition(condition: .onQueue(queue))
        commandConditions.append(condition)
    }

    func discoverServices(_ serviceUUIDs: [CBUUID], timeout: TimeInterval) throws {
        let servicesToDiscover = peripheral.servicesToDiscover(from: serviceUUIDs)

        guard servicesToDiscover.count > 0 else {
            return
        }

        try runCommand(timeout: timeout) {
            addCondition(.discoverServices)
            
            peripheral.discoverServices(serviceUUIDs)
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID], for service: CBService, timeout: TimeInterval) throws {
        let characteristicsToDiscover = peripheral.characteristicsToDiscover(from: characteristicUUIDs, for: service)

        guard characteristicsToDiscover.count > 0 else {
            return
        }

        try runCommand(timeout: timeout) {
            addCondition(.discoverCharacteristicsForService(serviceUUID: service.uuid))

            peripheral.discoverCharacteristics(characteristicsToDiscover, for: service)
        }
    }

    func reconnect(timeout: TimeInterval) throws {
        try runCommand(timeout: timeout) {
            addCondition(.connect)
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    /// - Throws: PeripheralManagerError
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic, timeout: TimeInterval) throws {
        try runCommand(timeout: timeout) {
            addCondition(.notificationStateUpdate(characteristicUUID: characteristic.uuid, enabled: enabled))

            peripheral.setNotifyValue(enabled, for: characteristic)
        }
    }

    /// - Throws: PeripheralManagerError
    func readValue(for characteristic: CBCharacteristic, timeout: TimeInterval) throws -> Data? {
        try runCommand(timeout: timeout) {
            addCondition(.valueUpdate(characteristic: characteristic, matching: nil))

            peripheral.readValue(for: characteristic)
        }

        return characteristic.value
    }

    /// - Throws: PeripheralManagerError
    func writeValue(_ value: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType, timeout: TimeInterval) throws {
        try runCommand(timeout: timeout) {
            if case .withResponse = type {
                addCondition(.write(characteristic: characteristic))
            }

            peripheral.writeValue(value, for: characteristic, type: type)
        }
    }
}

extension PeripheralManager {
    public override var debugDescription: String {
        var items = [
            "## PeripheralManager",
            "peripheral: \(peripheral)",
        ]
        queue.sync {
            items.append("needsConfiguration: \(needsConfiguration)")
        }
        return items.joined(separator: "\n")
    }
}

// MARK: - Delegate methods executed on the central's queue
extension PeripheralManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        log.default("didDiscoverServices")
        commandLock.lock()

        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .discoverServices = condition {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        commandLock.lock()

        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .discoverCharacteristicsForService(serviceUUID: service.uuid) = condition {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        commandLock.lock()

        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .notificationStateUpdate(characteristicUUID: characteristic.uuid, enabled: characteristic.isNotifying) = condition {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        commandLock.lock()
        
        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .write(characteristic: characteristic) = condition {
                return true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        commandLock.lock()
        
        if let macro = configuration.valueUpdateMacros[characteristic.uuid] {
            macro(self)
        }

        if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
            if case .valueUpdate(characteristic: characteristic, matching: let matching) = condition {
                return matching?(characteristic.value) ?? true
            } else {
                return false
            }
        }) {
            commandConditions.remove(at: index)
            commandError = error

            if commandConditions.isEmpty {
                commandLock.broadcast()
            }
        }

        commandLock.unlock()

    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else {
            self.log.error("Error reading rssi: %{public}@", String(describing: RSSI))
            return
        }
        self.log.default("didReadRSSI: %{public}@", String(describing: RSSI))
    }

}


extension PeripheralManager {

    func clearCommsQueues() {
        queueLock.lock()
        if cmdQueue.count > 0 {
            self.log.default("Removing %{public}d leftover elements from command queue", cmdQueue.count)
            cmdQueue.removeAll()
        }
        if dataQueue.count > 0 {
            self.log.default("Removing %{public}d leftover elements from data queue", dataQueue.count)
            dataQueue.removeAll()
        }
        queueLock.unlock()
    }

    func centralManager(_ central: CBCentralManager, didDisconnect peripheral: CBPeripheral, error: Error?) {
        self.queue.async {
            self.idleStart = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.log.debug("PeripheralManager - didConnect: %@", peripheral)
        switch peripheral.state {
        case .connected:
            clearCommsQueues()
            self.log.debug("PeripheralManager - didConnect - running assertConfiguration")
            assertConfiguration()

            commandLock.lock()
            if let index = commandConditions.firstIndex(where: { (condition) -> Bool in
                if case .connect = condition {
                    return true
                } else {
                    return false
                }
            }) {
                commandConditions.remove(at: index)

                if commandConditions.isEmpty {
                    commandLock.broadcast()
                }
            }
            commandLock.unlock()

        default:
            break
        }
    }
}

extension CBPeripheral {
    func getCommandCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(OmnipodServiceUUID.service.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(OmnipodCharacteristicUUID.command.cbUUID)
    }

    func getDataCharacteristic() -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(OmnipodServiceUUID.service.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(OmnipodCharacteristicUUID.data.cbUUID)
    }
}

// MARK: - Command session management
extension PeripheralManager {
    public func runSession(withName name: String , _ block: @escaping () -> Void) {
        self.log.default("Scheduling session %{public}@", name)

        sessionQueue.addOperation({ [weak self] in
            self?.perform { (manager) in
                manager.log.default("======================== %{public}@ ===========================", name)
                block()
                manager.log.default("------------------------ %{public}@ ---------------------------", name)
                self?.idleStart = Date()
                self?.log.default("Start of idle at %{public}@", String(describing: self?.idleStart))
            }
        })
    }
}
