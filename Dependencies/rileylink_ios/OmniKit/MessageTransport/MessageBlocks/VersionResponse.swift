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

    public let pmVersion: FirmwareVersion
    public let piVersion: FirmwareVersion
    public let podProgressStatus: PodProgressStatus
    public let lot: UInt32
    public let tid: UInt32
    public let gain: UInt8? // Only in the shorter assignAddress response
    public let rssi: UInt8? // Only in the shorter assignAddress response
    public let address: UInt32
    
    public let data: Data
    
    public init(encodedData: Data) throws {
        let responseLength = encodedData[1]
        data = encodedData.subdata(in: 0..<Int(responseLength + 2))

        switch responseLength {
        case assignAddressVersionLength:
            // This is the shorter 0x15 response to the 07 AssignAddress command
            // 01 15 020700 020700 02 02 0000a377 0003ab37 9f 1f00ee87
            // 0  1  2      5      8  9  10       14       18 19
            // 01 LL MXMYMZ IXIYIZ 02 0J LLLLLLLL TTTTTTTT GS IIIIIIII
            // LL = 0x15 (assignAddressVersionLength)
            // PM = MX.MY.MZ
            // PI = IX.IY.IZ
            // 0J = Pod progress state (typically 02, could be 01)
            // LLLLLLLL = Lot
            // TTTTTTTT = Tid
            // GS = ggssssss (Gain/RSSI)
            // IIIIIIII = address

            pmVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 2..<5))
            piVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 5..<8))
            if let podProgress = PodProgressStatus(rawValue: encodedData[9]) {
                self.podProgressStatus = podProgress
            } else {
                throw MessageBlockError.parseError
            }
            lot = encodedData[10...].toBigEndian(UInt32.self)
            tid = encodedData[14...].toBigEndian(UInt32.self)
            gain = (encodedData[18] & 0xc0) >> 6
            rssi = encodedData[18] & 0x3f
            address = encodedData[19...].toBigEndian(UInt32.self)
            
        case setupPodVersionLength:
            // This is the longer 0x1B response to the 03 SetupPod command
            // 01 1b 13881008340a50 020700 020700 02 03 0000a62b 00044794 1f00ee87
            // 0  1  2              9      12        16 17       21       25
            // 01 LL 13881008340A50 MXMYMZ IXIYIZ 02 0J LLLLLLLL TTTTTTTT IIIIIIII
            // LL = 0x1B (setupPodVersionMessageLength)
            // PM = MX.MY.MZ
            // PI = IX.IY.IZ
            // 0J = Pod progress state (should always be 03)
            // LLLLLLLL = Lot
            // TTTTTTTT = Tid
            // IIIIIIII = address

            pmVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 9..<12))
            piVersion = FirmwareVersion(encodedData: encodedData.subdata(in: 12..<15))
            if let podProgress = PodProgressStatus(rawValue: encodedData[16]) {
                self.podProgressStatus = podProgress
            } else {
                throw MessageBlockError.parseError
            }
            lot = encodedData[17...].toBigEndian(UInt32.self)
            tid = encodedData[21...].toBigEndian(UInt32.self)
            gain = nil // No GS byte in the longer SetupPod response
            rssi = nil // No GS byte in the longer SetupPod response
            address = encodedData[25...].toBigEndian(UInt32.self)

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
        return "VersionResponse(lot:\(lot), tid:\(tid), gain:\(gain?.description ?? "NA"), rssi:\(rssi?.description ?? "NA") address:\(Data(bigEndian: address).hexadecimalString), podProgressStatus:\(podProgressStatus), pmVersion:\(pmVersion), piVersion:\(piVersion))"
    }
}

