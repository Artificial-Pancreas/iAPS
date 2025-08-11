import Foundation
public extension UserDefaults {
    private enum Key: String {
        case sensor = "com.loopkit.libre2sensor"
        case calibrationMapping = "com.loopkit.libre2sensor-calibrationmapping"
        case currentSensorUid = "com.loopkit.libre2sensor-currentSensorUid"

    }
    
    var currentSensor: String? {
        get {
            string(forKey: Key.currentSensorUid.rawValue)
        }
        
        set {
            if let newValue {
                set(newValue, forKey: Key.currentSensorUid.rawValue)
            }
            else {
                removeObject(forKey: Key.currentSensorUid.rawValue)
            }
        }
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
            if let newValue {
                let encoder = JSONEncoder()
                if let encoded = try? encoder.encode(newValue) {
                    set(encoded, forKey: Key.sensor.rawValue)
                }
            } else {
                removeObject(forKey: Key.sensor.rawValue)
            }
        }
    }

    var calibrationMapping: CalibrationToSensorMapping? {
        get {
            if let sensor = object(forKey: Key.calibrationMapping.rawValue) as? Data {
                let decoder = JSONDecoder()
                return try? decoder.decode(CalibrationToSensorMapping.self, from: sensor)
            }

            return nil

        }
        set {
            if let newValue {
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

    public var age: Int?
    public var maxAge: Int

    public var unlockCount: Int
    
    var sensorName : String?
    var macAddress : String?

    public init(uuid: Data, patchInfo: Data, maxAge: Int, unlockCount: Int = 0, sensorName: String? = nil, macAddress: String? = nil) {
        self.uuid = uuid
        self.patchInfo = patchInfo
        self.unlockCount = 0
        self.maxAge = maxAge
        // self.calibrationInfo = calibrationInfo
        self.sensorName = sensorName
        self.macAddress = macAddress
    }

    public var description: String {
        return [
            "uuid: (\(uuid.hex))",
            "patchInfo: (\(patchInfo.hex))"
            // "calibrationInfo: (\(calibrationInfo.description))",
            // "family: \(family.description)",
            // "type: \(type.description)",
            // "region: \(region.description)",
            // "serial: \(serial ?? "Unknown")",
            // "state: \(state.description)",
            // "lifetime: \(lifetime.inTime)",
        ].joined(separator: ", ")
    }
}

private enum Key: String, CaseIterable {
    case sensorUnlockCount = "libre-direct.settings.sensor.unlockCount"
}
