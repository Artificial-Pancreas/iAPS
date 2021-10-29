import Foundation

enum CGMType: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }

    case nightscout
    case xdrip
    case dexcomG6
    case dexcomG5

    var displayName: String {
        switch self {
        case .nightscout:
            return "Nightscout"
        case .xdrip:
            return "xDrip"
        case .dexcomG6:
            return "Dexcom G6"
        case .dexcomG5:
            return "Dexcom G5"
        }
    }

    var appURL: URL? {
        switch self {
        case .nightscout:
            return nil
        case .xdrip:
            return URL(string: "xdripswift://")!
        case .dexcomG6:
            return URL(string: "dexcomg6://")!
        case .dexcomG5:
            return URL(string: "dexcomgcgm://")!
        }
    }
}
