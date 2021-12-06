import Foundation

enum CGMType: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }

    case nightscout
    case xdrip
    case dexcomG6
    case dexcomG5
    case simulator
    case libreTransmitter
    case glucoseDirect

    var displayName: String {
        switch self {
        case .nightscout:
            return "Nightscout"
        case .xdrip:
            return "xDrip"
        case .glucoseDirect:
            return "Glucose Direct"
        case .dexcomG6:
            return "Dexcom G6"
        case .dexcomG5:
            return "Dexcom G5"
        case .simulator:
            return NSLocalizedString("Glucose Simulator", comment: "Glucose Simulator CGM type")
        case .libreTransmitter:
            return NSLocalizedString("Libre Transmitter", comment: "Libre Transmitter type")
        }
    }

    var appURL: URL? {
        switch self {
        case .nightscout:
            return nil
        case .xdrip:
            return URL(string: "xdripswift://")!
        case .glucoseDirect:
            return URL(string: "libredirect://")!
        case .dexcomG6:
            return URL(string: "dexcomg6://")!
        case .dexcomG5:
            return URL(string: "dexcomgcgm://")!
        case .simulator:
            return nil
        case .libreTransmitter:
            return URL(string: "freeaps-x://libre-transmitter")!
        }
    }

    var externalLink: URL? {
        switch self {
        case .xdrip:
            return URL(string: "https://github.com/JohanDegraeve/xdripswift")!
        case .glucoseDirect:
            return URL(string: "https://github.com/creepymonster/GlucoseDirectApp")!
        default: return nil
        }
    }

    var subtitle: String {
        switch self {
        case .nightscout:
            return NSLocalizedString("Online or internal server", comment: "Online or internal server")
        case .xdrip:
            return NSLocalizedString("Shared app group", comment: "Shared app group")
        case .dexcomG6:
            return NSLocalizedString("Native G6 app", comment: "Native G6 app")
        case .dexcomG5:
            return NSLocalizedString("Native G5 app", comment: "Native G5 app")
        case .simulator:
            return NSLocalizedString("Simple simulator", comment: "Simple simulator")
        case .libreTransmitter:
            return NSLocalizedString(
                "Direct connection with Libre 1 transmitters or Libre 2",
                comment: "Direct connection with Libre 1 transmitters or Libre 2"
            )
        case .glucoseDirect:
            return NSLocalizedString("Shared app group", comment: "Shared app group")
        }
    }
}
