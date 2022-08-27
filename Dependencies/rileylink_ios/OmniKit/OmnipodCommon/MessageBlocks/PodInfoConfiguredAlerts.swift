//
//  PodInfoConfiguredAlerts.swift
//  OmniKit
//
//  Created by Eelke Jager on 16/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Type 1 Pod Info returns information about the currently configured alerts
public struct PodInfoConfiguredAlerts : PodInfo {
    // CMD 1  2  3 4  5 6  7 8  910 1112 1314 1516 1718 1920
    // DATA   0  1 2  3 4  5 6  7 8  910 1112 1314 1516 1718
    // 02 13 01 XXXX VVVV VVVV VVVV VVVV VVVV VVVV VVVV VVVV

    public let podInfoType : PodInfoResponseSubType = .configuredAlerts
    public let word_278    : Data
    public let alertsActivations : [AlertActivation]
    public let data       : Data

    public struct AlertActivation {
        let beepType: BeepType
        let unitsLeft: Double
        let timeFromPodStart: UInt8
        
        public init(beepType: BeepType, timeFromPodStart: UInt8, unitsLeft: Double) {
            self.beepType = beepType
            self.timeFromPodStart = timeFromPodStart
            self.unitsLeft = unitsLeft
        }
    }
    
    public init(encodedData: Data) throws {
        guard encodedData.count >= 11 else {
            throw MessageBlockError.notEnoughData
        }

        self.word_278 = encodedData[1...2]
        
        let numAlertTypes = 8
        let beepType = BeepType.self
        
        var activations = [AlertActivation]()

        for alarmType in (0..<numAlertTypes) {
            let beepType = beepType.init(rawValue: UInt8(alarmType))
            let timeFromPodStart = encodedData[(3 + alarmType * 2)] // Double(encodedData[(5 + alarmType)] & 0x3f)
            let unitsLeft = Double(encodedData[(4 + alarmType * 2)]) / Pod.pulsesPerUnit
            activations.append(AlertActivation(beepType: beepType!, timeFromPodStart: timeFromPodStart, unitsLeft: unitsLeft))
        }
        alertsActivations = activations
        self.data         = encodedData
    }
}
