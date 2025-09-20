import CGMBLEKit
import Foundation
import G7SensorKit
import LibreTransmitter
import LoopKit
import MinimedKit
import MockKit
import NightscoutRemoteCGM
import OmniBLE
import OmniKit

enum KnownPlugins {
    static func allowCalibrations(for cgmManager: CGMManager) -> Bool {
        cgmManager.pluginIdentifier == LibreTransmitterManagerV3.pluginIdentifier
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

    static func appURLByPluginIdentifier(pluginIdentifier: String) -> URL? {
        switch pluginIdentifier {
        case G5CGMManager.pluginIdentifier:
            URL(string: "dexcomgcgm://")!
        case G6CGMManager.pluginIdentifier:
            URL(string: "dexcomg6://")!
        case G7CGMManager.pluginIdentifier:
            URL(string: "dexcomg7://")!
        default: nil
        }
    }

    static func cgmIdForStatistics(for cgmManager: CGMManager?) -> String? {
        guard let cgmManager else { return nil }

        switch cgmManager.pluginIdentifier {
        case G5CGMManager.pluginIdentifier: return CGMType.dexcomG5.rawValue
        case G6CGMManager.pluginIdentifier: return CGMType.dexcomG6.rawValue
        case G7CGMManager.pluginIdentifier: return CGMType.dexcomG7.rawValue
        case LibreTransmitterManagerV3.pluginIdentifier: return CGMType.libreTransmitter.rawValue
        case NightscoutRemoteCGM.pluginIdentifier: return CGMType.nightscout.rawValue
        case MockCGMManager.pluginIdentifier: return CGMType.simulator.rawValue
        case MinimedPumpManager.pluginIdentifier: return CGMType.enlite.rawValue
        case AppGroupCGM.pluginIdentifier:
            guard let cgmManager = cgmManager as? AppGroupCGM else {
                return nil
            }
            return cgmManager.appGroupSource.latestReadingFrom?.rawValue ??
                cgmManager.appGroupSource.latestReadingFromOther
        default: return cgmManager.pluginIdentifier
        }
    }

    static func isManualTempBasalActive(_ pumpManager: PumpManager) -> Bool? {
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            if let omnipod = pumpManager as? OmnipodPumpManager,
               let tempBasal = omnipod.state.podState?.unfinalizedTempBasal,
               !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                return true
            } else {
                return false
            }
        case OmniBLEPumpManager.pluginIdentifier:
            if let omnipodBLE = pumpManager as? OmniBLEPumpManager,
               let tempBasal = omnipodBLE.state.podState?.unfinalizedTempBasal,
               !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                return true
            } else {
                return false
            }
        default: return nil
        }
    }

    static func pumpActivationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            return (pumpManager as? OmnipodPumpManager)?.state.podState?.activatedAt
        case OmniBLEPumpManager.pluginIdentifier:
            return (pumpManager as? OmniBLEPumpManager)?.state.podState?.activatedAt
        default: return nil
        }
    }

    static func pumpExpirationDate(_ pumpManager: PumpManager) -> Date? {
        switch pumpManager.pluginIdentifier {
        case OmnipodPumpManager.pluginIdentifier:
            return (pumpManager as? OmnipodPumpManager)?.state.podState?.expiresAt
        case OmniBLEPumpManager.pluginIdentifier:
            return (pumpManager as? OmniBLEPumpManager)?.state.podState?.expiresAt
        default: return nil
        }
    }
}
