import CGMBLEKit
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import MinimedKit
import OmniBLE
import OmniKit

enum KnownPlugins {
    enum Ids {
        static let libreTransmitter = LibreTransmitterManagerV3.pluginIdentifier
    }

    static func cgmExpirationByPluginIdentifier(_ cgmManager: CGMManager?) -> TimeInterval? {
        guard let cgmManager else { return nil }
        let secondsOfDay = 8.64E4

        return switch cgmManager.pluginIdentifier {
        case G6CGMManager.pluginIdentifier: 10 * secondsOfDay
        case G7CGMManager.pluginIdentifier: 10.5 * secondsOfDay
        case LibreTransmitterManagerV3.pluginIdentifier: 14.5 * secondsOfDay
        case MinimedPumpManager.pluginIdentifier: 6 * secondsOfDay
        default: nil
        }
    }

    static func pumpExpiration(pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            return (pumpManager as? OmnipodPumpManager)?.state.podState?.expiresAt
        case OmniBLEPumpManager.pluginIdentifier:
            return (pumpManager as? OmniBLEPumpManager)?.state.podState?.expiresAt
        default:
            return nil
        }
    }

    static func sessionStart(cgmManager: CGMManager) -> Date? {
        switch cgmManager.pluginIdentifier {
        case G5CGMManager.pluginIdentifier:
            return (cgmManager as? G5CGMManager)?.latestReading?.sessionStartDate
        case G6CGMManager.pluginIdentifier:
            return (cgmManager as? G6CGMManager)?.latestReading?.sessionStartDate
        case G7CGMManager.pluginIdentifier:
            return (cgmManager as? G7CGMManager)?.sensorFinishesWarmupAt
        case LibreTransmitterManagerV3.pluginIdentifier:
            return (cgmManager as? LibreTransmitterManagerV3)?.sensorInfoObservable.activatedAt
        default:
            return nil
        }
    }
}
