import Foundation

extension Bool {
    static func fromString(_ string: String) -> Bool? {
        switch string.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
}
