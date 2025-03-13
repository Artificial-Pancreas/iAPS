//
//  MiaoMiao.swift
//  LibreMonitor
//
//  Created by Uwe Petersen on 02.11.18.
//  Copyright © 2018 Uwe Petersen. All rights reserved.
//

import Foundation

public struct LibreTransmitterMetadata: CustomStringConvertible {
    // hardware number
    public let hardware: String
    // software number
    public let firmware: String
    // battery level, percentage between 0 % and 100 %
    public let battery: Int?
    // battery level String
    public let batteryString: String

    public let macAddress: String?

    public let name: String

    public let patchInfo: String?
    public let uid: [UInt8]?

    init(hardware: String, firmware: String, battery: Int?, name: String, macAddress: String?, patchInfo: String?, uid: [UInt8]?) {
        self.hardware = hardware
        self.firmware = firmware
        self.battery = battery
        let batteryString = battery == nil ? "-" : "\(battery!)"
        self.batteryString = batteryString
        self.macAddress = macAddress
        self.name = name
        self.patchInfo = patchInfo
        self.uid = uid
    }

    public var description: String {
        "Transmitter: \(name), Hardware: \(hardware), firmware: \(firmware)" +
        "battery: \(batteryString), macAddress: \(String(describing: macAddress)), patchInfo: \(String(describing: patchInfo)), uid: \(String(describing: uid))"
    }

    public func sensorType() -> SensorType? {
        guard let patchInfo = patchInfo else { return nil }
        return SensorType(patchInfo: patchInfo)
    }
}

extension String {
    //https://stackoverflow.com/questions/39677330/how-does-string-substring-work-in-swift
    //usage
    //let s = "hello"
    //s[0..<3] // "hel"
    //s[3..<s.count] // "lo"
    subscript(_ range: CountableRange<Int>) -> String {
        let idx1 = index(startIndex, offsetBy: max(0, range.lowerBound))
        let idx2 = index(startIndex, offsetBy: min(self.count, range.upperBound))
        return String(self[idx1..<idx2])
    }

    func hexadecimal() -> Data? {
        var data = Data(capacity: count / 2)

        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, range: NSRange(startIndex..., in: self)) { match, _, _ in
            let byteString = (self as NSString).substring(with: match!.range)
            let num = UInt8(byteString, radix: 16)!
            data.append(num)
        }

        guard data.count > 0 else { return nil }

        return data
    }
}

public enum SensorType: String, CustomStringConvertible {
    case libre1 = "DF"
    case libre1A2 = "A2"
    case libre2 = "9D"
    case libre2C5 = "C5"
    case libreUS14day = "E5"
    case libreUS14dayE6 = "E6"
    case libreProH = "70"
    case libre2Plus = "C6"

    public var description: String {
        switch self {
        case .libre1:
            return "Libre 1"
        case .libre1A2:
            return "Libre 1 A2"
            case .libre2, .libre2C5, .libre2Plus:
            return "Libre 2"
        case .libreUS14day, .libreUS14dayE6:
            return "Libre US"
        case .libreProH:
            return "Libre PRO H"
        }
    }
}

public extension SensorType {
    init?(patchInfo: String) {
        guard patchInfo.count > 1 else { return nil }

        let start = patchInfo[0..<2].uppercased()

        let choices: [String: SensorType] = ["DF": .libre1, "A2": .libre1A2, "9D": .libre2, "C5": .libre2C5, "C6": .libre2Plus, "E5": .libreUS14day, "E6": .libreUS14dayE6, "70": .libreProH]

        if let res = choices[start] {
            self = res
            return
        }

        return nil
    }
}
