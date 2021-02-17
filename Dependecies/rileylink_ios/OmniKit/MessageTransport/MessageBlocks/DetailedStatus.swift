//
//  DetailedStatus.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/23/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// DetailedStatus is the PodInfo subtype 2 returned for a type 2 GetStatus command and
// is also returned on a pod fault for any command normally returning a StatusResponse
public struct DetailedStatus : PodInfo, Equatable {
    // CMD 1  2  3  4  5 6  7  8 9 10 1112 1314 1516 17 18 19 20 21 2223
    // DATA   0  1  2  3 4  5  6 7  8  910 1112 1314 15 16 17 18 19 2021
    // 02 16 02 0J 0K LLLL MM NNNN PP QQQQ RRRR SSSS TT UU VV WW 0X YYYY

    public let podInfoType: PodInfoResponseSubType = .detailedStatus
    public let podProgressStatus: PodProgressStatus
    public let deliveryStatus: DeliveryStatus
    public let bolusNotDelivered: Double
    public let podMessageCounter: UInt8
    public let totalInsulinDelivered: Double
    public let faultEventCode: FaultEventCode
    public let faultEventTimeSinceActivation: TimeInterval?
    public let reservoirLevel: Double?
    public let timeActive: TimeInterval
    public let unacknowledgedAlerts: AlertSet
    public let faultAccessingTables: Bool
    public let errorEventInfo: ErrorEventInfo?
    public let receiverLowGain: UInt8
    public let radioRSSI: UInt8
    public let previousPodProgressStatus: PodProgressStatus?
    public let unknownValue: Data
    public let data: Data
    
    public init(encodedData: Data) throws {
        guard encodedData.count >= 21 else {
            throw MessageBlockError.notEnoughData
        }
        
        guard PodProgressStatus(rawValue: encodedData[1]) != nil else {
            throw MessageError.unknownValue(value: encodedData[1], typeDescription: "PodProgressStatus")
        }
        self.podProgressStatus = PodProgressStatus(rawValue: encodedData[1])!
        
        self.deliveryStatus = DeliveryStatus(rawValue: encodedData[2] & 0xf)!
        
        self.bolusNotDelivered = Pod.pulseSize * Double((Int(encodedData[3] & 0x3) << 8) | Int(encodedData[4]))
        
        self.podMessageCounter = encodedData[5]
        
        self.totalInsulinDelivered = Pod.pulseSize * Double(encodedData[6...7].toBigEndian(UInt16.self))
        
        self.faultEventCode = FaultEventCode(rawValue: encodedData[8])
        
        let minutesSinceActivation = encodedData[9...10].toBigEndian(UInt16.self)
        if minutesSinceActivation != 0xffff {
            self.faultEventTimeSinceActivation = TimeInterval(minutes: Double(minutesSinceActivation))
        } else {
            self.faultEventTimeSinceActivation = nil
        }
        
        let reservoirValue = Double((Int(encodedData[11] & 0x3) << 8) + Int(encodedData[12])) * Pod.pulseSize
        
        if reservoirValue <= Pod.maximumReservoirReading {
            self.reservoirLevel = reservoirValue
        } else {
            self.reservoirLevel =  nil
        }
        
        self.timeActive = TimeInterval(minutes: Double(encodedData[13...14].toBigEndian(UInt16.self)))
        
        self.unacknowledgedAlerts =  AlertSet(rawValue: encodedData[15])
        
        self.faultAccessingTables = encodedData[16] == 2
        
        if encodedData[17] == 0x00 {
           self.errorEventInfo = nil // this byte is not valid (no fault has occurred)
        } else {
            self.errorEventInfo = ErrorEventInfo(rawValue: encodedData[17])
        }
        
        self.receiverLowGain = UInt8(encodedData[18] >> 6)
        self.radioRSSI =  UInt8(encodedData[18] & 0x3F)
        
        if encodedData[19] == 0xFF {
            self.previousPodProgressStatus = nil // this byte is not valid (no fault has occurred)
        } else {
            self.previousPodProgressStatus = PodProgressStatus(rawValue: encodedData[19] & 0xF)!
        }
        
        self.unknownValue = encodedData[20...21]
        
        self.data = Data(encodedData)
    }

    public var isFaulted: Bool {
        return faultEventCode.faultType != .noFaults || podProgressStatus == .activationTimeExceeded
    }

    // Returns an appropropriate PDM style Ref string for the Detailed Status.
    // For most types, Ref: TT-VVVHH-IIIRR-FFF computed as {19|17}-{VV}{SSSS/60}-{NNNN/20}{RRRR/20}-PP
    public var pdmRef: String? {
        let TT, VVV, HH, III, RR, FFF: UInt8
        let refStr = LocalizedString("Ref", comment: "PDM style 'Ref' string")

        switch faultEventCode.faultType {
        case .noFaults, .reservoirEmpty, .exceededMaximumPodLife80Hrs:
            return nil      // no PDM Ref # generated for these cases
        case .insulinDeliveryCommandError:
            // This fault is treated as a PDM fault which uses an alternate Ref format
            return String(format: "%@:\u{00a0}11-144-0018-00049", refStr) // all fixed values for this fault
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

        if let reservoirLevel = self.reservoirLevel {
            RR = UInt8(reservoirLevel)
        } else {
            RR = 51         // value used for 50+ U
        }

        return String(format: "%@:\u{00a0}%02d-%03d%02d-%03d%02d-%03d", refStr, TT, VVV, HH, III, RR, FFF)
    }
}

extension DetailedStatus: CustomDebugStringConvertible {
    public typealias RawValue = Data
    public var debugDescription: String {
        return [
            "## DetailedStatus",
            "* rawHex: \(data.hexadecimalString)",
            "* podProgressStatus: \(podProgressStatus)",
            "* deliveryStatus: \(deliveryStatus.description)",
            "* bolusNotDelivered: \(bolusNotDelivered.twoDecimals) U",
            "* podMessageCounter: \(podMessageCounter)",
            "* totalInsulinDelivered: \(totalInsulinDelivered.twoDecimals) U",
            "* faultEventCode: \(faultEventCode.description)",
            "* faultEventTimeSinceActivation: \(faultEventTimeSinceActivation?.stringValue ?? "none")",
            "* reservoirLevel: \(reservoirLevel?.twoDecimals ?? "50+") U",
            "* timeActive: \(timeActive.stringValue)",
            "* unacknowledgedAlerts: \(unacknowledgedAlerts)",
            "* faultAccessingTables: \(faultAccessingTables)",
            "* errorEventInfo: \(errorEventInfo?.description ?? "NA")",
            "* receiverLowGain: \(receiverLowGain)",
            "* radioRSSI: \(radioRSSI)",
            "* previousPodProgressStatus: \(previousPodProgressStatus?.description ?? "NA")",
            "* unknownValue: 0x\(unknownValue.hexadecimalString)",
            "",
            ].joined(separator: "\n")
    }
}

extension DetailedStatus: RawRepresentable {
    public init?(rawValue: Data) {
        do {
            try self.init(encodedData: rawValue)
        } catch {
            return nil
        }
    }
    
    public var rawValue: Data {
        return data
    }
}

extension TimeInterval {
    var stringValue: String {
        let totalSeconds = self
        let minutes = Int(totalSeconds / 60) % 60
        let hours = Int(totalSeconds / 3600) - (Int(self / 3600)/24 * 24)
        let days = Int((totalSeconds / 3600) / 24)
        var pluralFormOfDays = "days"
        if days == 1 {
            pluralFormOfDays = "day"
        }
        let timeComponent = String(format: "%02d:%02d", hours, minutes)
        if days > 0 {
            return String(format: "%d \(pluralFormOfDays) plus %@", days, timeComponent)
        } else {
            return timeComponent
        }
    }
}

extension Double {
    var twoDecimals: String {
        let reservoirLevel = self
        return String(format: "%.2f", reservoirLevel)
    }
}

// Type for the ErrorEventInfo VV byte if valid
//    a: insulin state table corruption found during error logging
//   bb: internal 2-bit variable set and manipulated in main loop routines
//    c: immediate bolus in progress during error
// dddd: Pod Progress at time of first logged fault event
//
public struct ErrorEventInfo: CustomStringConvertible, Equatable {
    let rawValue: UInt8
    let insulinStateTableCorruption: Bool // 'a' bit
    let internalVariable: Int // 'bb' 2-bit internal variable
    let immediateBolusInProgress: Bool // 'c' bit
    let podProgressStatus: PodProgressStatus // 'dddd' bits

    public var errorEventInfo: ErrorEventInfo? {
        return ErrorEventInfo(rawValue: rawValue)
    }

    public var description: String {
        let hexString = String(format: "%02X", rawValue)
        return [
            "rawValue: 0x\(hexString)",
            "insulinStateTableCorruption: \(insulinStateTableCorruption)",
            "internalVariable: \(internalVariable)",
            "immediateBolusInProgress: \(immediateBolusInProgress)",
            "podProgressStatus: \(podProgressStatus)",
            ].joined(separator: ", ")
    }

    init(rawValue: UInt8)  {
        self.rawValue = rawValue
        self.insulinStateTableCorruption = (rawValue & 0x80) != 0
        self.internalVariable = Int((rawValue & 0x60) >> 5)
        self.immediateBolusInProgress = (rawValue & 0x10) != 0
        self.podProgressStatus = PodProgressStatus(rawValue: rawValue & 0xF)!
    }
}


extension DetailedStatus {
    var highlightText: String {
        switch faultEventCode.faultType {
        case .exceededMaximumPodLife80Hrs:
            return LocalizedString("Pod Expired", comment: "Highlight string for pod expired (80hrs).")
        default:
            return LocalizedString("Pod Fault", comment: "Highlight string for pod faults.")
        }
    }
}
