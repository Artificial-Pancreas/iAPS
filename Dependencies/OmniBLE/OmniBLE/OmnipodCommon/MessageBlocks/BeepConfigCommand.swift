//
//  BeepConfigCommand.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/BeepConfigCommand.swift
//  Created by Joseph Moran on 5/12/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation

public struct BeepConfigCommand : MessageBlock {
    // OFF 1  2 3 4 5
    // 1e 04 AABBCCDD

    public let blockType: MessageBlockType = .beepConfig
    public let beepConfigType: BeepConfigType
    public let basalCompletionBeep: Bool
    public let basalIntervalBeep: TimeInterval
    public let tempBasalCompletionBeep: Bool
    public let tempBasalIntervalBeep: TimeInterval
    public let bolusCompletionBeep: Bool
    public let bolusIntervalBeep: TimeInterval

    public init(beepConfigType: BeepConfigType, basalCompletionBeep: Bool = false, basalIntervalBeep: TimeInterval = 0, tempBasalCompletionBeep: Bool = false, tempBasalIntervalBeep: TimeInterval = 0, bolusCompletionBeep: Bool = false, bolusIntervalBeep: TimeInterval = 0) {
        self.beepConfigType = beepConfigType
        self.basalCompletionBeep = basalCompletionBeep
        self.basalIntervalBeep = basalIntervalBeep
        self.tempBasalCompletionBeep = tempBasalCompletionBeep
        self.tempBasalIntervalBeep = tempBasalIntervalBeep
        self.bolusCompletionBeep = bolusCompletionBeep
        self.bolusIntervalBeep = bolusIntervalBeep
    }

    public init(encodedData: Data) throws {
        if encodedData.count < 6 {
            throw MessageBlockError.notEnoughData
        }
        if let beepConfigType = BeepConfigType.init(rawValue: encodedData[2]) {
            self.beepConfigType = beepConfigType
        } else {
            throw MessageBlockError.parseError
        }
        self.basalCompletionBeep = encodedData[3] & (1<<6) != 0
        self.basalIntervalBeep = TimeInterval(minutes: Double(encodedData[3] & 0x3f))
        self.tempBasalCompletionBeep = encodedData[4] & (1<<6) != 0
        self.tempBasalIntervalBeep = TimeInterval(minutes: Double(encodedData[4] & 0x3f))
        self.bolusCompletionBeep = encodedData[5] & (1<<6) != 0
        self.bolusIntervalBeep = TimeInterval(minutes: Double(encodedData[5] & 0x3f))
    }

    public var data: Data {
        var data = Data([
            blockType.rawValue,
            4,
            ])
        data.append(beepConfigType.rawValue)
        data.append((basalCompletionBeep ? (1<<6) : 0) + (UInt8(basalIntervalBeep.minutes) & 0x3f))
        data.append((tempBasalCompletionBeep ? (1<<6) : 0) + (UInt8(tempBasalIntervalBeep.minutes) & 0x3f))
        data.append((bolusCompletionBeep ? (1<<6) : 0) + (UInt8(bolusIntervalBeep.minutes) & 0x3f))
        return data
    }
}

extension BeepConfigCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "BeepConfigCommand(beepConfigType:\(beepConfigType), basalIntervalBeep:\(basalIntervalBeep), tempBasalCompletionBeep:\(tempBasalCompletionBeep), tempBasalIntervalBeep:\(tempBasalIntervalBeep), bolusCompletionBeep:\(bolusCompletionBeep), , bolusIntervalBeep:\(bolusIntervalBeep))"
    }
}
