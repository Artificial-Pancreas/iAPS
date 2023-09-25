//
//  MessagePacket.swift
//  DanaKit
//
//  Created by Randall Knutson on 8/4/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//
import Foundation
import CoreBluetooth

struct MessagePacket {

    class BLEComm {
        private let rh: ResourceHelper
        private let context: Context
        private let rxBus: RxBus
        private let sp: SP
        private let danaMessageHashTable: danaMessageHashTable
        private let danaPump: DanaPump
        private let danaPlugin: DanaPlugin
        private let bleEncryption: BleEncryption
        private let pumpSync: PumpSync
        private let dateUtil: DateUtil

        init(
            rh: ResourceHelper,
            context: Context,
            rxBus: RxBus,
            sp: SP,
            danaMessageHashTable: DanaMessageHashTable,
            danaPump: DanaPump,
            danaPlugin: DanaPlugin,
            bleEncryption: BleEncryption,
            pumpSync: PumpSync,
            dateUtil: DateUtil
        ) {
            self.rh = rh
            self.context = context
            self.rxBus = rxBus
            self.sp = sp
            self.danaMessageHashTable = danaMessageHashTable
            self.danaPump = danaPump
            self.danaPlugin = danaPlugin
            self.bleEncryption = bleEncryption
            self.pumpSync = pumpSync
            self.dateUtil = dateUtil
        }
    }

    private static let WRITE_DELAY_MILLIS: Int64 = 50
    private static let UART_READ_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"
    private static let UART_WRITE_UUID = "0000fff2-0000-1000-8000-00805f9b34fb"
    private static let UART_BLE5_UUID = "00002902-0000-1000-8000-00805f9b34fb"
    
    private static let PACKET_START_BYTE = 0xA5
    private static let PACKET_END_BYTE = 0x5A
    private static let BLE5_PACKET_END_BYTE = 0xEE
    
    var scheduledDisconnection: ScheduledFuture<Any>? = nil
    var processedMessage: DanaPacket? = nil
    var msendQueue = [Data]()
    
    let bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    let bluetoothAdapter = bluetoothManager?.adapter

    var connectDeviceName: String? = nil
    var encryption: EncryptionType = .ENCRYPTION_DEFAULT {
        didSet {
            bleEncryption.setEnhancedEncryption(newValue)
        }
    }

    var isEasyMode: Bool = false
    var isUnitUD: Bool = false
    var isConnected = false
    var isConnecting = false
    private var encryptedDataRead = false
    private var encryptedCommandSent = false
    private var uartRead: BluetoothGattCharacteristic? = nil
    private var uartWrite: BluetoothGattCharacteristic? = nil
    
    if #available(iOS 15.0, *), !CBManager.authorization == .allowedAlways {
        ToastUtils.errorToast(context, context.localizedString(forKey: "needconnectpermission", value: nil, table: "Localizable"))
        OSLog.error(LTag.pumpBTCOMM, "missing permission: \(from)")
        return false
    }

    OSLog.debug(LTag.pumpBTCOMM, "Initializing BLEComm.")

    if bluetoothAdapter == nil {
        OSLog.error("Unable to obtain a BluetoothAdapter.")
        return false
    }

    if address == nil {
        OSLog.error("unspecified address.")
        return false
    }
    
    if let device = bluetoothAdapter?.getRemoteDevice(address) {
        if device.bondState == .none {
            if #available(iOS 15.0, *), CBManager.authorization != .allowedAlways {
                device.createBond()
                Thread.sleep(forTimeInterval: 10)
            }
            return false
        }
        
        isConnected = false
        encryption = .encryptionDefault
        encryptedDataRead = false
        encryptedCommandSent = false
        isConnecting = true
        bufferLength = 0
        OSLog.debug(LTag.pumpBTCOMM, "Trying to create a new connection from: \(from)")
        connectDeviceName = device.name
        bluetoothGatt = device.connectGatt(context, false, mGattCallback)
        setCharacteristicNotification(uartReadBTGattChar, enabled: true)
        return true
    } else {
        OSLog.error("Device not found. Unable to connect from: \(from)")
        return false
    }
        
    func stopConnecting() {
        isConnecting = false
    }
    
    func disconnect(from: String) {
        if #available(iOS 15.0, *), CBManager.authorization != .allowedAlways {
            OSLog.error(LTag.pumpBTCOMM, "missing permission: \(from)")
            return
        }
            
        OSLog.debug(LTag.pumpBTCOMM, "disconnect from: \(from)")

        if !encryptedDataRead && encryptedCommandSent && encryption == .encryptionBLE5 {
            // There was no response from pump after starting encryption.
            // Assume pairing keys are invalid.
            let lastClearRequest = sp.getLong(R.string.key_rs_last_clear_key_request, 0)
                
            if lastClearRequest != 0 && dateUtil.isOlderThan(lastClearRequest, 5) {
                ToastUtils.showToastInUiThread(context, R.string.invalidpairing)
                danaPlugin.changePump()
                removeBond()
            } else if lastClearRequest == 0 {
                OSLog.error("Clearing pairing keys postponed")
                sp.putLong(R.string.key_rs_last_clear_key_request, dateUtil.now())
            }
        }
    }
        if !encryptedDataRead && encryptedCommandSent && encryption == .encryptionRSv3 {
            // There was no response from the pump after starting encryption.
            // Assume pairing keys are invalid.
            let lastClearRequest = sp.getLong(R.string.key_rs_last_clear_key_request, 0)
            
            if lastClearRequest != 0 && dateUtil.isOlderThan(lastClearRequest, 5) {
                aapsLogger.error("Clearing pairing keys !!!")
                sp.remove(rh.gs(R.string.key_dana_v3_randompairingkey) + danaPlugin.mDeviceName)
                sp.remove(rh.gs(R.string.key_dana_v3_pairingkey) + danaPlugin.mDeviceName)
                sp.remove(rh.gs(R.string.key_dana_v3_randomsynckey) + danaPlugin.mDeviceName)
                ToastUtils.showToastInUiThread(context, R.string.invalidpairing)
                danaPlugin.changePump()
            } else if lastClearRequest == 0 {
                OSLog.error("Clearing pairing keys postponed")
                sp.putLong(R.string.key_rs_last_clear_key_request, dateUtil.now())
            }
        }
    // Cancel previous scheduled disconnection to prevent closing upcoming connection
    scheduledDisconnection?.cancel(false)
    scheduledDisconnection = nil

    if bluetoothAdapter == nil || bluetoothGatt == nil {
        OSLog.error("disconnect not possible: (mBluetoothAdapter == nil) \(bluetoothAdapter == nil)")
        OSLog.error("disconnect not possible: (mBluetoothGatt == nil) \(bluetoothGatt == nil)")
        return
    }

    setCharacteristicNotification(uartReadBTGattChar, enabled: false)
    bluetoothGatt?.disconnect()
    isConnected = false
    encryptedDataRead = false
    encryptedCommandSent = false
    Thread.sleep(forTimeInterval: 2)
    
    private func removeBond() {
        if let address = sp.string(forKey: R.string.key_dana_address) {
            if let device = bluetoothAdapter?.retrievePeripherals(withIdentifiers: [UUID(uuidString: address)!]).first {
                // Disconnect the device (if it's connected)
                if device.state == .connected {
                    bluetoothGatt?.cancelPeripheralConnection(device)
                }

                // Unpair the device
                if #available(iOS 15.0, *) {
                    if device.isPaired {
                        do {
                            try device.unpair()
                        } catch {
                            OSLog.error("Removing bond has failed. \(error.localizedDescription)")
                        }
                    }
                } else {
                    // Handle unpairing for older iOS versions
                    // Note: Unpairing is restricted on iOS, and you may not have direct control over it.
                    // Depending on your specific use case, you may not be able to unpair devices programmatically.
                    OSLog.error("Removing bond is not supported on this iOS version.")
                }
            }
        }
    }
}
