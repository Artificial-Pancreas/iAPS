//
//  DetailedStatus+OmniBLE.swift
//  OmniBLE
//
//  Created by Joseph Moran on 01/07/2022
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

// Returns an appropropriate Dash PDM style Ref string for DetailedStatus
extension DetailedStatus {
    // For most types, Ref: TT-VVVHH-IIIRR-FFF computed as {20|19|18|17|16|15|14|07|01}-{VV}{SSSS/60}-{NNNN/20}{RRRR/20}-PP
    public var pdmRef: String? {
        let TT: UInt8
        var VVV: UInt8 = data[17] // default value, can be changed
        let HH: UInt8 = UInt8(timeActive.hours)
        let III: UInt8 = UInt8(totalInsulinDelivered)
        let RR: UInt8 = UInt8(self.reservoirLevel) // special 51.15 value used for > 50U will become 51 as needed
        var FFF: UInt8 = faultEventCode.rawValue // default value, can be changed

        switch faultEventCode.faultType {
        case .noFaults:
            return nil
        case .failedFlashErase ,.failedFlashStore, .tableCorruptionBasalSubcommand, .corruptionByte720, .corruptionInWord129, .disableFlashSecurityFailed:
            // Ref: 01-VVVHH-IIIRR-FFF
            TT = 01         // RAM Ref type
        case .badTimerVariableState, .problemCalibrateTimer, .rtcInterruptHandlerUnexpectedCall, .trimICSTooCloseTo0x1FF,
          .problemFindingBestTrimValue, .badSetTPM1MultiCasesValue:
            // Ref: 07-VVVHH-IIIRR-FFF
            TT = 07         // Clock Ref type
        case .insulinDeliveryCommandError:
            // Ref: 11-144-0018-0049, this fault is treated as a PDM fault with an alternate Ref format
            // XXX need to verify these values are still correct with the Dash PDM
            return "11-144-0018-00049" // all fixed values for this fault
        case .reservoirEmpty:
            // Ref: 14-VVVHH-IIIRR-FFF
            TT = 14         // PumpVolume Ref type
        case .autoOff0, .autoOff1, .autoOff2, .autoOff3, .autoOff4, .autoOff5, .autoOff6, .autoOff7:
            // Ref: 15-VVVHH-IIIRR-FFF
            TT = 15         // PumpAutoOff Ref type
        case .exceededMaximumPodLife80Hrs:
            // Ref: 16-VVVHH-IIIRR-FFF
            TT = 16         // PumpExpired Ref type
        case .occluded:
            // Ref: 17-000HH-IIIRR-000
            TT = 17         // PumpOcclusion Ref type
            VVV = 0         // no VVV value for an occlusion fault
            FFF = 0         // no FFF value for an occlusion fault
        case .bleTimeout, .bleInitiated, .bleUnkAlarm, .bleIaas, .crcFailure, .bleWdPingTimeout, .bleExcessiveResets, .bleNakError, .bleReqHighTimeout, .bleUnknownResp, .bleReqStuckHigh, .bleStateMachine1, .bleStateMachine2, .bleArbLost, .bleEr48DualNack, .bleQnExceedMaxRetry, .bleQnCritVarFail:
            // Ref: 20-VVVHH-IIIRR-FFF
            TT = 20         // PumpCommunications Ref type
        default:
            // Ref: 19-VVVHH-IIIRR-FFF
            TT = 19         // PumpError Ref type
        }

        return String(format: "%02d-%03d%02d-%03d%02d-%03d", TT, VVV, HH, III, RR, FFF)
    }
}
