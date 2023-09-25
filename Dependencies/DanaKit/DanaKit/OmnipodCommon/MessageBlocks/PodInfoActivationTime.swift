//
//  PodInfoActivationTime.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/PodInfoResponseSubType.swift
//  Created by Eelke Jager on 25/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Type 5 PodInfo returns the pod activation time, time pod alive, and the possible fault code
public struct PodInfoActivationTime : PodInfo {
    // OFF 1  2  3  4 5  6 7 8 9 10111213 1415161718
    // DATA   0  1  2 3  4 5 6 7 8 9 1011 1213141516
    // 02 11 05 PP QQQQ 00000000 00000000 MMDDYYHHMM

    public let podInfoType: PodInfoResponseSubType = .activationTime
    public let faultEventCode: FaultEventCode
    public let timeActivation: TimeInterval
    public let dateTime: DateComponents
    public let data: Data
    
    public init(encodedData: Data) throws {
        guard encodedData.count >= 16 else {
            throw MessageBlockError.notEnoughData
        }
        self.faultEventCode = FaultEventCode(rawValue: encodedData[1])
        self.timeActivation = TimeInterval(minutes: Double((Int(encodedData[2] & 0b1) << 8) + Int(encodedData[3])))
        self.dateTime = DateComponents(encodedDateTime: encodedData.subdata(in: 12..<17))
        self.data = Data(encodedData)
    }
}

extension DateComponents {
    init(encodedDateTime: Data) {
        self.init()
        
        year   = Int(encodedDateTime[2]) + 2000
        month  = Int(encodedDateTime[0])
        day    = Int(encodedDateTime[1])
        hour   = Int(encodedDateTime[3])
        minute = Int(encodedDateTime[4])
        
        calendar = Calendar(identifier: .gregorian)
    }
}
