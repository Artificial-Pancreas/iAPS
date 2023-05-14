//
//  DetailedStatus+OmniKit.swift
//  OmniKit
//
//  Created by Joseph Moran on 06/22/2022
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

// Returns an appropropriate PDM style Ref string for the Detailed Status.
// For most types, Ref: TT-VVVHH-IIIRR-FFF computed as {19|17}-{VV}{SSSS/60}-{NNNN/20}{RRRR/20}-PP
extension DetailedStatus {
    public var pdmRef: String? {
        let TT, VVV, HH, III, RR, FFF: UInt8

        switch faultEventCode.faultType {
        case .noFaults, .reservoirEmpty, .exceededMaximumPodLife80Hrs:
            return nil      // no PDM Ref # generated for these cases
        case .insulinDeliveryCommandError:
            // This fault is treated as a PDM fault which uses an alternate Ref format
            return "11-144-0018-00049" // all fixed values for this fault
        case .occluded:
            // Ref: 17-000HH-IIIRR-000
            TT = 17         // Occlusion detected Ref type
            VVV = 0         // no VVV value for an occlusion fault
            FFF = 0         // no FFF value for an occlusion fault
        default:
            // Ref: 19-VVVHH-IIIRR-FFF
            TT = 19         // pod fault Ref type
            VVV = data[17]  // use the raw VV byte value
            FFF = faultEventCode.rawValue
        }

        HH = UInt8(timeActive.hours)
        III = UInt8(totalInsulinDelivered)

        RR = UInt8(self.reservoirLevel) // special 51.15 value used for > 50U will become 51 as needed

        return String(format: "%02d-%03d%02d-%03d%02d-%03d", TT, VVV, HH, III, RR, FFF)
    }
}
