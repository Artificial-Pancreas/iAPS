import Foundation

public extension UserDefaults {
    private enum Key: String {
        case sensor = "no.bjorninge.libre2sensor"
        case calibrationMapping = "no.bjorninge.libre2sensor-calibrationmapping"


    }

    var preSelectedSensor: Sensor? {
        get {

            if let sensor = object(forKey: Key.sensor.rawValue) as? Data {
                let decoder = JSONDecoder()
                return try? decoder.decode(Sensor.self, from: sensor)
            }

            return nil

        }
        set {
            if let newValue = newValue {
                let encoder = JSONEncoder()
                if let encoded = try? encoder.encode(newValue) {
                    set(encoded, forKey: Key.sensor.rawValue)
                }
            } else {
                removeObject(forKey: Key.sensor.rawValue)
            }
        }
    }

    var calibrationMapping : CalibrationToSensorMapping? {
        get {
            if let sensor = object(forKey: Key.calibrationMapping.rawValue) as? Data {
                let decoder = JSONDecoder()
                return try? decoder.decode(CalibrationToSensorMapping.self, from: sensor)
            }

            return nil

        }
        set {
            if let newValue = newValue {
                let encoder = JSONEncoder()
                if let encoded = try? encoder.encode(newValue) {
                    set(encoded, forKey: Key.calibrationMapping.rawValue)
                }
            } else {
                removeObject(forKey: Key.calibrationMapping.rawValue)
            }
        }
    }
}

public struct CalibrationToSensorMapping: Codable {
    public let uuid: Data
    public let reverseFooterCRC: Int

    public init(uuid: Data, reverseFooterCRC: Int) {
        self.uuid = uuid
        self.reverseFooterCRC = reverseFooterCRC
    }
}


public struct Sensor: Codable {
    public let uuid: Data
    public let patchInfo: Data
   // public let calibrationInfo: SensorData.CalibrationInfo

    //public let family: SensorFamily
    //public let type: SensorType
    //public let region: SensorRegion
    //public let serial: String?
    //public var state: SensorState
    public var age: Int? = nil
    public var maxAge: Int
   // public var lifetime: Int

    public var unlockCount: Int

    /*
    public var unlockCount: Int {
        get {
            return UserDefaults.standard.integer(forKey: Key.sensorUnlockCount.rawValue)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: Key.sensorUnlockCount.rawValue)
        }
    }*/

    /*
    public var elapsedLifetime: Int? {
        get {
            if let remainingLifetime = remainingLifetime {
                return max(0, lifetime - remainingLifetime)
            }

            return nil
        }
    }

    public var remainingLifetime: Int? {
        get {
            if let age = age {
                return max(0, lifetime - age)
            }

            return nil
        }
    } */

    public init(uuid: Data, patchInfo: Data, maxAge:Int, unlockCount: Int = 0) {
        self.uuid = uuid
        self.patchInfo = patchInfo

        //self.family = SensorFamily(patchInfo: patchInfo)
        //self.type = SensorType(patchInfo: patchInfo)
        //self.region = SensorRegion(patchInfo: patchInfo)
        //self.serial = sensorSerialNumber(sensorUID: self.uuid, sensorFamily: self.family)
        //self.state = SensorState(fram: fram)
        //self.lifetime = Int(fram[327]) << 8 + Int(fram[326])
        self.unlockCount = 0
        self.maxAge = maxAge
        //self.calibrationInfo = calibrationInfo
    }

    public var description: String {
        return [
            "uuid: (\(uuid.hex))",
            "patchInfo: (\(patchInfo.hex))",
            //"calibrationInfo: (\(calibrationInfo.description))",
            //"family: \(family.description)",
            //"type: \(type.description)",
            //"region: \(region.description)",
            //"serial: \(serial ?? "Unknown")",
            //"state: \(state.description)",
            //"lifetime: \(lifetime.inTime)",
        ].joined(separator: ", ")
    }
}

fileprivate enum Key: String, CaseIterable {
    case sensorUnlockCount = "libre-direct.settings.sensor.unlockCount"
}

/*
fileprivate func sensorSerialNumber(sensorUID: Data, sensorFamily: SensorFamily) -> String? {
    let lookupTable = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "Q", "R", "T", "U", "V", "W", "X", "Y", "Z"]

    guard sensorUID.count == 8 else {
        return nil
    }

    let bytes = Array(sensorUID.reversed().suffix(6))
    var fiveBitsArray = [UInt8]()
    fiveBitsArray.append(bytes[0] >> 3)
    fiveBitsArray.append(bytes[0] << 2 + bytes[1] >> 6)

    fiveBitsArray.append(bytes[1] >> 1)
    fiveBitsArray.append(bytes[1] << 4 + bytes[2] >> 4)

    fiveBitsArray.append(bytes[2] << 1 + bytes[3] >> 7)

    fiveBitsArray.append(bytes[3] >> 2)
    fiveBitsArray.append(bytes[3] << 3 + bytes[4] >> 5)

    fiveBitsArray.append(bytes[4])

    fiveBitsArray.append(bytes[5] >> 3)
    fiveBitsArray.append(bytes[5] << 2)

    return fiveBitsArray.reduce("\(sensorFamily.rawValue)", {
        $0 + lookupTable[Int(0x1F & $1)]
    })
}
 */
