//
//  Libre2DirectTransmitter.swift


import CoreBluetooth
import Foundation
import os.log
import UIKit




class Libre2DirectTransmitter: LibreTransmitterProxyProtocol {
    

    fileprivate lazy var logger = Logger(forType: Self.self)

    func reset() {
        rxBuffer.resetAllBytes()
    }

    class var manufacturerer: String {
        "Abbott"
    }

    class var smallImage: UIImage? {
        UIImage(named: "libresensor", in: Bundle.module, compatibleWith: nil)
    }

    class var shortTransmitterName: String {
        "libre2"
    }

    class var requiresDelayedReconnect : Bool {
        false
    }

    private let expectedBufferSize = 46
    static var requiresSetup = true
    static var requiresPhoneNFC: Bool = true

    static var writeCharacteristic: UUIDContainer? = "F001"//0000f001-0000-1000-8000-00805f9b34fb"
    static var notifyCharacteristic: UUIDContainer? = "F002"//"0000f002-0000-1000-8000-00805f9b34fb"
    //static var serviceUUID: [UUIDContainer] = ["0000fde3-0000-1000-8000-00805f9b34fb"]
    static var serviceUUID: [UUIDContainer] = ["FDE3"]

    weak var delegate: LibreTransmitterDelegate?

    private var rxBuffer = Data()
    private var sensorData: SensorData?
    private var metadata: LibreTransmitterMetadata?

    class func canSupportPeripheral(_ peripheral: CBPeripheral) -> Bool {
        peripheral.name?.lowercased().starts(with: "abbott") ?? false
    }

    class func getDeviceDetailsFromAdvertisement(advertisementData: [String: Any]?) -> String? {
        nil
    }

    required init(delegate: LibreTransmitterDelegate, advertisementData: [String: Any]?) {
        //advertisementData is unknown for the miaomiao
        self.delegate = delegate
    }

    func requestData(writeCharacteristics: CBCharacteristic, peripheral: CBPeripheral) {
        //because of timing issues, we cannot use this method on libre2 eu sensors
    }

    func updateValueForNotifyCharacteristics(_ value: Data, peripheral: CBPeripheral, writeCharacteristic: CBCharacteristic?) {
        rxBuffer.append(value)

        logger.debug("libre2 direct Appended value with length  \(String(describing: value.count)), buffer length is: \(String(describing: self.rxBuffer.count))")


        if rxBuffer.count == expectedBufferSize {
            handleCompleteMessage()
        }


    }



    func didDiscoverWriteCharacteristics(_ peripheral: CBPeripheral, writeCharacteristics: CBCharacteristic) {

        guard let unlock = unlock() else{
            logger.debug("Cannot unlock sensor, aborting")
            return
        }

        logger.debug("Writing streaming unlock code to peripheral: \(unlock.hexEncodedString())")
        peripheral.writeValue(unlock, for: writeCharacteristics, type: .withResponse)


    }



    func didDiscoverNotificationCharacteristic(_ peripheral: CBPeripheral, notifyCharacteristic: CBCharacteristic) {

        logger.debug("libre2: saving notifyCharacteristic")
        //peripheral.setNotifyValue(true, for: notifyCharacteristic)
        logger.debug("libre2 setting notify while discovering : \(String(describing: notifyCharacteristic.debugDescription))")
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }


    private func unlock() -> Data? {

        guard var sensor = UserDefaults.standard.preSelectedSensor else {
            logger.debug("impossible to unlock sensor")
            return nil
        }

        sensor.unlockCount = sensor.unlockCount + 1

        UserDefaults.standard.preSelectedSensor = sensor

        let unlockPayload = Libre2.streamingUnlockPayload(sensorUID: sensor.uuid, info: sensor.patchInfo, enableTime: 42, unlockCount: UInt16(sensor.unlockCount))
        return Data(unlockPayload)

    }

    func handleCompleteMessage() {
        guard rxBuffer.count >= expectedBufferSize else {
            logger.debug("libre2 handle complete message with incorrect buffersize")
            reset()
            return
        }

        guard let sensor = UserDefaults.standard.preSelectedSensor else {
            logger.debug("libre2 handle complete message without sensorinfo present")
            reset()
            return
        }


        do {
            let decryptedBLE = Data(try Libre2.decryptBLE(id: [UInt8](sensor.uuid), data: [UInt8](rxBuffer)))
            let sensorUpdate = Libre2.parseBLEData(decryptedBLE)

            metadata = LibreTransmitterMetadata(hardware: "-", firmware: "-", battery: 100, name:  Self.shortTransmitterName, macAddress: nil, patchInfo: sensor.patchInfo.hexEncodedString().uppercased(), uid: [UInt8](sensor.uuid))

            delegate?.libreSensorDidUpdate(with: sensorUpdate, and: metadata!)

            print("libre2 got sensorupdate: \(String(describing: sensorUpdate))")

        } catch {

        }

        reset()

    }


}
