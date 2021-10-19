//
//  RileyLinkDevice.swift
//  RileyLinkBLEKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import CoreBluetooth
import os.log


/// TODO: Should we be tracking the most recent "pump" RSSI?
public class RileyLinkDevice {
    let manager: PeripheralManager

    private let log = OSLog(category: "RileyLinkDevice")

    // Confined to `manager.queue`
    private var bleFirmwareVersion: BLEFirmwareVersion?

    // Confined to `manager.queue`
    private var radioFirmwareVersion: RadioFirmwareVersion?

    // Confined to `lock`
    private var idleListeningState: IdleListeningState = .disabled

    // Confined to `lock`
    private var lastIdle: Date?
    
    // Confined to `lock`
    // TODO: Tidy up this state/preference machine
    private var isIdleListeningPending = false

    // Confined to `lock`
    private var isTimerTickEnabled = true
    
    // Confined to `lock`
    private var logs = ""

    /// Serializes access to device state
    private var lock = os_unfair_lock()
    
    private var fw_hw = "FW/HW"
    public var ledOn: Bool = false
    public var vibrationOn: Bool = false
    public var voltage = ""

    /// The queue used to serialize sessions and observe when they've drained
    private let sessionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.rileylink.RileyLinkBLEKit.RileyLinkDevice.sessionQueue"
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    private var sessionQueueOperationCountObserver: NSKeyValueObservation!

    init(peripheralManager: PeripheralManager) {
        self.manager = peripheralManager
        sessionQueue.underlyingQueue = peripheralManager.queue

        peripheralManager.delegate = self

        sessionQueueOperationCountObserver = sessionQueue.observe(\.operationCount, options: [.new]) { [weak self] (queue, change) in
            if let newValue = change.newValue, newValue == 0 {
                self?.log.debug("Session queue operation count is now empty")
                self?.assertIdleListening(forceRestart: true)
            }
        }
    }
}


// MARK: - Peripheral operations. Thread-safe.
extension RileyLinkDevice {
    public var name: String? {
        return manager.peripheral.name
    }

    public var deviceURI: String {
        return "rileylink://\(name ?? peripheralIdentifier.uuidString)"
    }

    public var peripheralIdentifier: UUID {
        return manager.peripheral.identifier
    }

    public var peripheralState: CBPeripheralState {
        return manager.peripheral.state
    }

    public func readRSSI() {
        guard case .connected = manager.peripheral.state, case .poweredOn? = manager.central?.state else {
            return
        }
        manager.peripheral.readRSSI()
    }

    public func setCustomName(_ name: String) {
        manager.setCustomName(name)
    }
    
    public func getBatterylevel() -> String {
        do {
            return try manager.readBatteryLevel(timeout: 1)
        } catch {}
        return ""
    }
    
    public func orangeAction(mode: Int) {
        add(log: "orangeAction: \(mode)")
        manager.orangeAction(mode: RileyLinkOrangeMode(rawValue: UInt8(mode))!)
    }
    
    public func orangeSetAction(index: Int, open: Bool) {
        add(log: "orangeSetAction: \(index), \(open)")
        manager.setAction(index: index, open: open)
    }
    
    public func orangeWritePwd() {
        add(log: "orangeWritePwd")
        manager.orangeWritePwd()
    }
    
    public func orangeClose() {
        add(log: "orangeClose")
        manager.orangeClose()
    }
    
    public func orangeReadSet() {
        add(log: "orangeReadSet")
        manager.orangeReadSet()
    }
    
    public func orangeReadVDC() {
        add(log: "orangeReadVDC")
        manager.orangeReadVDC()
    }
    
    public func enableBLELEDs() {
        manager.setLEDMode(mode: .on)
    }

    /// Asserts that the caller is currently on the session queue
    public func assertOnSessionQueue() {
        dispatchPrecondition(condition: .onQueue(manager.queue))
    }

    /// Schedules a closure to execute on the session queue after a specified time
    ///
    /// - Parameters:
    ///   - deadline: The time after which to execute
    ///   - execute: The closure to execute
    public func sessionQueueAsyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) {
        manager.queue.asyncAfter(deadline: deadline, execute: execute)
    }
}


extension RileyLinkDevice: Equatable, Hashable {
    public static func ==(lhs: RileyLinkDevice, rhs: RileyLinkDevice) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(peripheralIdentifier)
    }
}


// MARK: - Status management
extension RileyLinkDevice {
    public struct Status {
        public let lastIdle: Date?

        public let name: String?

        public let bleFirmwareVersion: BLEFirmwareVersion?

        public let radioFirmwareVersion: RadioFirmwareVersion?
        
        public let fw_hw: String?
        
        public var ledOn: Bool = false
        public var vibrationOn: Bool = false
        public var voltage = ""
    }

    public func getStatus(_ completion: @escaping (_ status: Status) -> Void) {
        os_unfair_lock_lock(&lock)
        let lastIdle = self.lastIdle
        os_unfair_lock_unlock(&lock)

        self.manager.queue.async {
            completion(Status(
                lastIdle: lastIdle,
                name: self.name,
                bleFirmwareVersion: self.bleFirmwareVersion,
                radioFirmwareVersion: self.radioFirmwareVersion,
                fw_hw: self.fw_hw,
                ledOn: self.ledOn,
                vibrationOn: self.vibrationOn,
                voltage: self.voltage
            ))
        }
    }
}


// MARK: - Command session management
extension RileyLinkDevice {
    public func runSession(withName name: String, _ block: @escaping (_ session: CommandSession) -> Void) {
        sessionQueue.addOperation(manager.configureAndRun({ [weak self] (manager) in
            self?.log.default("======================== %{public}@ ===========================", name)
            let bleFirmwareVersion = self?.bleFirmwareVersion
            let radioFirmwareVersion = self?.radioFirmwareVersion

            if bleFirmwareVersion == nil || radioFirmwareVersion == nil {
                self?.log.error("Running session with incomplete configuration: bleFirmwareVersion %{public}@, radioFirmwareVersion: %{public}@", String(describing: bleFirmwareVersion), String(describing: radioFirmwareVersion))
            }

            block(CommandSession(manager: manager, responseType: bleFirmwareVersion?.responseType ?? .buffered, firmwareVersion: radioFirmwareVersion ?? .unknown))
            self?.log.default("------------------------ %{public}@ ---------------------------", name)
        }))
    }
}


// MARK: - Idle management
extension RileyLinkDevice {
    public enum IdleListeningState {
        case enabled(timeout: TimeInterval, channel: UInt8)
        case disabled
    }

    func setIdleListeningState(_ state: IdleListeningState) {
        os_unfair_lock_lock(&lock)
        let oldValue = idleListeningState
        idleListeningState = state
        os_unfair_lock_unlock(&lock)

        switch (oldValue, state) {
        case (.disabled, .enabled):
            assertIdleListening(forceRestart: true)
        case (.enabled, .enabled):
            assertIdleListening(forceRestart: false)
        default:
            break
        }
    }

    public func assertIdleListening(forceRestart: Bool = false) {
        os_unfair_lock_lock(&lock)
        guard case .enabled(timeout: let timeout, channel: let channel) = self.idleListeningState else {
            os_unfair_lock_unlock(&lock)
            return
        }

        guard case .connected = self.manager.peripheral.state, case .poweredOn? = self.manager.central?.state else {
            os_unfair_lock_unlock(&lock)
            return
        }

        guard forceRestart || (self.lastIdle ?? .distantPast).timeIntervalSinceNow < -timeout else {
            os_unfair_lock_unlock(&lock)
            return
        }

        guard !self.isIdleListeningPending else {
            os_unfair_lock_unlock(&lock)
            return
        }

        self.isIdleListeningPending = true
        os_unfair_lock_unlock(&lock)
        self.log.debug("Enqueuing idle listening")

        self.manager.startIdleListening(idleTimeout: timeout, channel: channel) { (error) in
            os_unfair_lock_lock(&self.lock)
            self.isIdleListeningPending = false

            if let error = error {
                self.log.error("Unable to start idle listening: %@", String(describing: error))
                os_unfair_lock_unlock(&self.lock)
            } else {
                self.lastIdle = Date()
                os_unfair_lock_unlock(&self.lock)
                NotificationCenter.default.post(name: .DeviceDidStartIdle, object: self)
            }
        }
    }
}


// MARK: - Timer tick management
extension RileyLinkDevice {
    func setTimerTickEnabled(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        self.isTimerTickEnabled = enabled
        os_unfair_lock_unlock(&lock)
        self.assertTimerTick()
    }

    func assertTimerTick() {
        os_unfair_lock_lock(&self.lock)
        let isTimerTickEnabled = self.isTimerTickEnabled
        os_unfair_lock_unlock(&self.lock)

        if isTimerTickEnabled != self.manager.timerTickEnabled {
            self.manager.setTimerTickEnabled(isTimerTickEnabled)
        }
    }
}


// MARK: - CBCentralManagerDelegate Proxying
extension RileyLinkDevice {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if case .poweredOn = central.state {
            assertIdleListening(forceRestart: false)
            assertTimerTick()
        }

        manager.centralManagerDidUpdateState(central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.debug("didConnect %@", peripheral)
        if case .connected = peripheral.state {
            assertIdleListening(forceRestart: false)
            assertTimerTick()
        }

        manager.centralManager(central, didConnect: peripheral)
        NotificationCenter.default.post(name: .DeviceConnectionStateDidChange, object: self)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.debug("didDisconnectPeripheral %@", peripheral)
        NotificationCenter.default.post(name: .DeviceConnectionStateDidChange, object: self)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.debug("didFailToConnect %@", peripheral)
        NotificationCenter.default.post(name: .DeviceConnectionStateDidChange, object: self)
    }
}


extension RileyLinkDevice: PeripheralManagerDelegate {
    func peripheralManager(_ manager: PeripheralManager, didUpdateNotificationStateFor characteristic: CBCharacteristic) {
        add(log: "didUpdate: \(characteristic.uuid.uuidString)")
//        switch OrangeServiceCharacteristicUUID(rawValue: characteristic.uuid.uuidString) {
//        case .orange, .orangeNotif:
//            manager.writePsw = true
//            orangeWritePwd()
//        default:
//            break
//        }
        log.debug("Did didUpdateNotificationStateFor %@", characteristic)
    }
    
    // This is called from the central's queue
    func peripheralManager(_ manager: PeripheralManager, didUpdateValueFor characteristic: CBCharacteristic) {
        log.debug("Did UpdateValueFor %@", characteristic)
        add(log: "Did UpdateValueFor: \(characteristic.uuid.uuidString), value: \(characteristic.value?.hexadecimalString ?? "")")
        switch MainServiceCharacteristicUUID(rawValue: characteristic.uuid.uuidString) {
        case .data?:
            guard let value = characteristic.value, value.count > 0 else {
                return
            }

            self.manager.queue.async {
                if let responseType = self.bleFirmwareVersion?.responseType {
                    let response: PacketResponse?

                    switch responseType {
                    case .buffered:
                        var buffer =  ResponseBuffer<PacketResponse>(endMarker: 0x00)
                        buffer.append(value)
                        response = buffer.responses.last
                    case .single:
                        response = PacketResponse(data: value)
                    }

                    if let response = response {
                        switch response.code {
                        case .rxTimeout, .commandInterrupted, .zeroData, .invalidParam, .unknownCommand:
                            self.log.debug("Idle error received: %@", String(describing: response.code))
                        case .success:
                            if let packet = response.packet {
                                self.log.debug("Idle packet received: %@", value.hexadecimalString)
                                NotificationCenter.default.post(
                                    name: .DevicePacketReceived,
                                    object: self,
                                    userInfo: [RileyLinkDevice.notificationPacketKey: packet]
                                )
                            }
                        }
                    } else {
                        self.log.error("Unknown idle response: %@", value.hexadecimalString)
                    }
                } else {
                    self.log.error("Skipping parsing characteristic value update due to missing BLE firmware version")
                }

                self.resetBatteryAlert()
                self.orangeReadVDC()
                self.assertIdleListening(forceRestart: true)
            }
        case .responseCount?:
            // PeripheralManager.Configuration.valueUpdateMacros is responsible for handling this response.
            self.resetBatteryAlert()
            self.orangeReadVDC()
            break
        case .timerTick?:
            NotificationCenter.default.post(name: .DeviceTimerDidTick, object: self)
            self.resetBatteryAlert()
            self.orangeReadVDC()
            assertIdleListening(forceRestart: false)
        case .customName?, .firmwareVersion?, .ledMode?, .none:
            break
        }
        
        switch OrangeServiceCharacteristicUUID(rawValue: characteristic.uuid.uuidString) {
        case .orange, .orangeNotif:
            guard let data = characteristic.value, !data.isEmpty else { return }
            if data.first == 0xbb {
                guard let data = characteristic.value, data.count > 6 else { return }
                if data[1] == 0x09, data[2] == 0xaa {
                    fw_hw = "FW\(data[3]).\(data[4])/HW\(data[5]).\(data[6])"
                    NotificationCenter.default.post(name: .DeviceFW_HWChange, object: self)
                }
            } else if data.first == 0xdd {
                guard let data = characteristic.value, data.count > 2 else { return }
                if data[1] == 0x01 {
                    guard let data = characteristic.value, data.count > 5 else { return }
                    ledOn = (data[3] != 0)
                    vibrationOn = (data[4] != 0)
                    NotificationCenter.default.post(name: .DeviceFW_HWChange, object: self)
                } else if data[1] == 0x03 {
                    guard var data = characteristic.value, data.count > 4 else { return }
                    data = Data(data[3...4])
                    let int = UInt16(bigEndian: data.withUnsafeBytes { $0.load(as: UInt16.self) })
                    voltage = String(format: "%.1f%", Float(int) / 1000)
                    NotificationCenter.default.post(name: .DeviceFW_HWChange, object: self)
                    
                    guard Date() > Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "voltage_date")).addingTimeInterval(60 * 60),
                          UserDefaults.standard.double(forKey: "voltage_alert_value") != 0 else { return }
                    
                    UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: "voltage_date")
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                        let value = UserDefaults.standard.double(forKey: "voltage_alert_value")
                        if (Double(self.voltage) ?? 100) <= value {
                            let content = UNMutableNotificationContent()
                            content.title = "Low Voltage"
                            content.subtitle = self.voltage
                            let request = UNNotificationRequest.init(identifier: "Orange Low Voltage", content: content, trigger: nil)
                            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                        }
                    }
                }
            }
        default:
            break
        }
    }
    
    func resetBatteryAlert() {
        guard Date() > Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "battery_date")).addingTimeInterval(60 * 60) else { return }
        if UserDefaults.standard.integer(forKey: "battery_alert_value") != 0 {
            manager.queue.async {
                UserDefaults.standard.setValue(Date().timeIntervalSince1970, forKey: "battery_date")
                let batteryLevel = self.getBatterylevel()
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    let value = UserDefaults.standard.integer(forKey: "battery_alert_value")
                    if (Int(batteryLevel) ?? 100) <= value {
                        let content = UNMutableNotificationContent()
                        content.title = "Low Battery"
                        content.subtitle = batteryLevel
                        let request = UNNotificationRequest.init(identifier: "Orange Low Battery", content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                    }
                }
            }
        }
    }

    func peripheralManager(_ manager: PeripheralManager, didReadRSSI RSSI: NSNumber, error: Error?) {
        NotificationCenter.default.post(
            name: .DeviceRSSIDidChange,
            object: self,
            userInfo: [RileyLinkDevice.notificationRSSIKey: RSSI]
        )
    }

    func peripheralManagerDidUpdateName(_ manager: PeripheralManager) {
        NotificationCenter.default.post(
            name: .DeviceNameDidChange,
            object: self,
            userInfo: nil
        )
    }

    func completeConfiguration(for manager: PeripheralManager) throws {
        // Read bluetooth version to determine compatibility
        log.default("Reading firmware versions for PeripheralManager configuration")
        let bleVersionString = try manager.readBluetoothFirmwareVersion(timeout: 1)
        bleFirmwareVersion = BLEFirmwareVersion(versionString: bleVersionString)

        let radioVersionString = try manager.readRadioFirmwareVersion(timeout: 1, responseType: bleFirmwareVersion?.responseType ?? .buffered)
        radioFirmwareVersion = RadioFirmwareVersion(versionString: radioVersionString)
        
        try manager.setOrangeNotifyOn()
    }
}


extension RileyLinkDevice: CustomDebugStringConvertible {
    
    public func add(log: String) {
        os_unfair_lock_lock(&lock)
        if self.logs.count > 10000 {
            self.logs.removeLast(1000)
        }
        self.logs.append("\(Date())\n\(log)\n")
        os_unfair_lock_unlock(&lock)
    }
    
    public var debugDescription: String {
        os_unfair_lock_lock(&lock)
        let lastIdle = self.lastIdle
        let isIdleListeningPending = self.isIdleListeningPending
        let isTimerTickEnabled = self.isTimerTickEnabled
        os_unfair_lock_unlock(&lock)

        return [
            "## RileyLinkDevice",
            "* name: \(name ?? "")",
            "* lastIdle: \(lastIdle ?? .distantPast)",
            "* isIdleListeningPending: \(isIdleListeningPending)",
            "* isTimerTickEnabled: \(isTimerTickEnabled)",
            "* isTimerTickNotifying: \(manager.timerTickEnabled)",
            "* radioFirmware: \(String(describing: radioFirmwareVersion))",
            "* bleFirmware: \(String(describing: bleFirmwareVersion))",
            "* peripheralManager: \(manager)",
            "* sessionQueue.operationCount: \(sessionQueue.operationCount)",
            "* logs: \(logs)",
            "* manager logs: \(manager.logString)"
        ].joined(separator: "\n")
    }
}


extension RileyLinkDevice {
    public static let notificationPacketKey = "com.rileylink.RileyLinkBLEKit.RileyLinkDevice.NotificationPacket"

    public static let notificationRSSIKey = "com.rileylink.RileyLinkBLEKit.RileyLinkDevice.NotificationRSSI"
}


extension Notification.Name {
    public static let DeviceConnectionStateDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.ConnectionStateDidChange")

    public static let DeviceDidStartIdle = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.DidStartIdle")

    public static let DeviceNameDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.NameDidChange")

    public static let DevicePacketReceived = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.PacketReceived")

    public static let DeviceRSSIDidChange = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.RSSIDidChange")

    public static let DeviceTimerDidTick = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.TimerTickDidChange")
    
    public static let DeviceFW_HWChange = Notification.Name(rawValue: "com.rileylink.RileyLinkBLEKit.DeviceFW_HWChange")
}
