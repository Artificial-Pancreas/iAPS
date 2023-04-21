//
//  VersionResponse.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/12/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

fileprivate let assignAddressVersionLength: UInt8 = 0x15
fileprivate let setupPodVersionLength: UInt8 = 0x1B

public struct VersionResponse : MessageBlock {
    
    public struct FirmwareVersion : CustomStringConvertible {
        let major: UInt8
        let minor: UInt8
        let patch: UInt8
        
        public init(encodedData: Data) {
            major = encodedData[0]
            minor = encodedData[1]
            patch = encodedData[2]
        }
        
        public var description: String {
            return "\(major).\(minor).\(patch)"
        }
    }
    
    public let blockType: MessageBlockType = .versionResponse

    public let firmwareVersion: FirmwareVersion     // for Eros (PM) 2.x.y, for NXP Dash 3.x.y, for TWI Dash 4.x.y
    public let iFirmwareVersion: FirmwareVersion    // for Eros (PI) same as PM, for Dash BLE firmware version #
    public let productId: UInt8                     // 02 for Eros, 04 for Dash, perhaps 05 for Omnipod 5
    public let lot: UInt32
    public let tid: UInt32
    public let address: UInt32
    public let podProgressStatus: PodProgressStatus

    // These values only included in the shorter 0x15 VersionResponse for the AssignAddress command for Eros.
    public let gain: UInt8?                         // 2-bit value, max gain is at 0, min gain is at 2
    public let rssi: UInt8?                         // 6-bit value, max rssi seen 61

    // These values only included in the longer 0x1B VersionResponse for the SetupPod command.
    public let pulseSize: Double?                   // VVVV / 100,000, must be 0x1388 / 100,000 = 0.05U
    public let secondsPerBolusPulse: Double?        // BR / 8, nominally 0x10 / 8 = 2 seconds per pulse
    public let secondsPerPrimePulse: Double?        // PR / 8, nominally 0x08 / 8 = 1 seconds per priming pulse
    public let primeUnits: Double?                  // PP / pulsesPerUnit, nominally 0x34 / 20 = 2.6U
    public let cannulaInsertionUnits: Double?       // CP / pulsesPerUnit, nominally 0x0A / 20 = 0.5U
    public let serviceDuration: TimeInterval?       // PL hours, nominally 0x50 = 80 hours

    public let data: Data
    
    public init(encodedData: Data) throws {
        let responseLength = encodedData[1]
        data = encodedData.subdata(in: 0..<Int(responseLength + 2))

        switch responseLength {
        case assignAddressVersionLength:
            // This is the shorter 0x15 response for the 07 AssignAddress command.
            // 0  1  2      5      8  9  10       14       18 19
            // 01 LL MXMYMZ IXIYIZ ID 0J LLLLLLLL TTTTTTTT GS IIIIIIII
            // 01 15 020700 020700 02 02 0000a377 0003ab37 9f 1f00ee87
            //
            // LL = 0x15 (assignAddressVersionLength)
            // PM MX.MY.MZ = 02.07.02 (for PM 2.7.0)
            // PI IX.IY.IZ = 02.07.02 (for PI 2.7.0)
            // ID = Product Id (02 for Eros, 04 for Dash, and perhaps 05 for Omnnipod 5)
            // 0J = Pod progress state (typically 02 for this particular response)
            // LLLLLLLL = Lot
            // TTTTTTTT = Tid
            // GS = ggssssss (Gain/RSSI for Eros only)
            // IIIIIIII = connection ID address

            firmwareVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 2..<5))
            iFirmwareVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 5..<8))
            productId = encodedData[8]
            guard let progressStatus = PodProgressStatus(rawValue: encodedData[9]) else {
                throw MessageBlockError.parseError
            }
            podProgressStatus = progressStatus
            lot = encodedData[10...].toBigEndian(UInt32.self)
            tid = encodedData[14...].toBigEndian(UInt32.self)
            gain = (encodedData[18] & 0xc0) >> 6
            rssi = encodedData[18] & 0x3f
            address = encodedData[19...].toBigEndian(UInt32.self)
            
            // These values only included in the longer 0x1B VersionResponse for the 03 SetupPod command.
            pulseSize = nil
            secondsPerBolusPulse = nil
            secondsPerPrimePulse = nil
            primeUnits = nil
            cannulaInsertionUnits = nil
            serviceDuration = nil

        case setupPodVersionLength:
            // This is the longer 0x1B response for the 03 SetupPod command.
            // 0  1  2    4  5  6  7  8  9      12     15 16 17       21       25
            // 01 LL VVVV BR PR PP CP PL MXMYMZ IXIYIZ ID 0J LLLLLLLL TTTTTTTT IIIIIIII
            // 01 1b 1388 10 08 34 0a 50 020700 020700 02 03 0000a62b 00044794 1f00ee87
            //
            // LL = 0x1b (setupPodVersionMessageLength)
            // VVVV = 0x1388, pulse Volume in micro-units of U100 insulin per tenth of pulse (5000/100000 = 0.05U per pulse)
            // BR = 0x10, Basic pulse Rate in # of eighth secs per pulse (16/8 = 2 seconds per pulse)
            // PR = 0x08, Prime pulse Rate in # of eighth secs per pulse for priming boluses (8/8 = 1 second per priming pulse)
            // PP = 0x34 = 52, # of Prime Pulses (52 pulses x 0.05U/pulse = 2.6U)
            // CP = 0x0A = 10, # of Cannula insertion Pulses (10 pulses x 0.05U/pulse = 0.5U)
            // PL = 0x50 = 80, # of hours maximum Pod Life
            // PM = MX.MY.MZ = 02.07.02 (for PM 2.7.0 for Eros)
            // PI = IX.IY.IZ = 02.07.02 (for PI 2.7.0 for Eros)
            // ID = Product Id (02 for Eros, 04 for Dash, and perhaps 05 for Omnnipod 5)
            // 0J = Pod progress state (should be 03 for this particular response)
            // LLLLLLLL = Lot
            // TTTTTTTT = Tid
            // IIIIIIII = connection ID address

            firmwareVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 9..<12))
            iFirmwareVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 12..<15))
            productId = encodedData[15]
            guard let progressStatus = PodProgressStatus(rawValue: encodedData[16]) else {
                throw MessageBlockError.parseError
            }
            podProgressStatus = progressStatus
            lot = encodedData[17...].toBigEndian(UInt32.self)
            tid = encodedData[21...].toBigEndian(UInt32.self)
            address = encodedData[25...].toBigEndian(UInt32.self)

            // These values should be verified elsewhere and appropriately handled.
            pulseSize = Double(encodedData[2...].toBigEndian(UInt16.self)) / 100000
            secondsPerBolusPulse = Double(encodedData[4]) / 8
            secondsPerPrimePulse = Double(encodedData[5]) / 8
            primeUnits = Double(encodedData[6]) / Pod.pulsesPerUnit
            cannulaInsertionUnits = Double(encodedData[7]) / Pod.pulsesPerUnit
            serviceDuration = TimeInterval.hours(Double(encodedData[8]))

            // These values only included in the shorter 0x15 VersionResponse for the AssignAddress command for Eros.
            gain = nil
            rssi = nil

        default:
            throw MessageBlockError.parseError
        }
    }

    public var isAssignAddressVersionResponse: Bool {
        return self.data.count == assignAddressVersionLength + 2
    }

    public var isSetupPodVersionResponse: Bool {
        return self.data.count == setupPodVersionLength + 2
    }
}

extension VersionResponse: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "VersionResponse(lot:\(lot), tid:\(tid), address:\(Data(bigEndian: address).hexadecimalString), firmwareVersion:\(firmwareVersion), iFirmwareVersion:\(iFirmwareVersion), productId:\(productId), podProgressStatus:\(podProgressStatus), gain:\(gain?.description ?? "NA"), rssi:\(rssi?.description ?? "NA"), pulseSize:\(pulseSize?.description ?? "NA"), secondsPerBolusPulse:\(secondsPerBolusPulse?.description ?? "NA"), secondsPerPrimePulse:\(secondsPerPrimePulse?.description ?? "NA"), primeUnits:\(primeUnits?.description ?? "NA"), cannulaInsertionUnits:\(cannulaInsertionUnits?.description ?? "NA"), serviceDuration:\(serviceDuration?.description ?? "NA"), )"
    }
}

