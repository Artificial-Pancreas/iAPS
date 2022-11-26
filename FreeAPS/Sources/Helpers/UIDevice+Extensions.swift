import SwiftUI

extension UIDevice {
    var getDeviceId: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        func mapToDevice(identifier: String) -> String {
            switch identifier {
            case "iPhone11,8":
                return "iPhone XR (A12)"

            case "iPhone12,1":
                return "iPhone 11 (A13)"
            case "iPhone12,8":
                return "iPhone SE (2nd Gen) (A13)"

            case "iPhone13,2":
                return "iPhone 12 (A14)"
            case "iPhone13,3":
                return "iPhone 12 Pro (A14)"
            case "iPhone13,4":
                return "iPhone 12 Pro Max (A14)"

            case "iPhone14,4":
                return "iPhone 13 mini (A15)"
            case "iPhone14,5":
                return "iPhone 13 (A15)"
            case "iPhone14,6":
                return "iPhone SE (3rd Gen) (A15)"
            case "iPhone14,7":
                return "iPhone 14 (A15)"

            case "iPhone15,2":
                return "iPhone 14 Pro (A16)"

            default:
                return identifier
            }
        }

        return mapToDevice(identifier: identifier)
    }

    var getOSInfo: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return String(os.majorVersion) + "." + String(os.minorVersion) + "." + String(os.patchVersion)
    }
}
