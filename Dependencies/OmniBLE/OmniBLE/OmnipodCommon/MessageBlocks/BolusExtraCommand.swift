//
//  BolusExtraCommand.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/BolusExtraCommand.swift
//  Created by Pete Schwamb on 2/24/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct BolusExtraCommand : MessageBlock {
    
    public let blockType: MessageBlockType = .bolusExtra
    
    public let acknowledgementBeep: Bool
    public let completionBeep: Bool
    public let programReminderInterval: TimeInterval
    public let units: Double
    public let timeBetweenPulses: TimeInterval
    public let squareWaveUnits: Double
    public let squareWaveDuration: TimeInterval

    // 17 0d 7c 1770 00030d40 0000 00000000
    // 0  1  2  3    5        9    13
    public var data: Data {
        let beepOptions = (UInt8(programReminderInterval.minutes) & 0x3f) + (completionBeep ? (1<<6) : 0) + (acknowledgementBeep ? (1<<7) : 0)

        var data = Data([
            blockType.rawValue,
            0x0d,
            beepOptions
            ])
        
        data.appendBigEndian(UInt16(round(units * 200)))
        data.appendBigEndian(UInt32(timeBetweenPulses.hundredthsOfMilliseconds))
        
        let pulseCountX10 = UInt16(round(squareWaveUnits * 200))
        data.appendBigEndian(pulseCountX10)
        
        let timeBetweenExtendedPulses = pulseCountX10 > 0 ? squareWaveDuration / Double(pulseCountX10) : 0
        data.appendBigEndian(UInt32(timeBetweenExtendedPulses.hundredthsOfMilliseconds))
        return data
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 15 {
            throw MessageBlockError.notEnoughData
        }
        
        acknowledgementBeep = encodedData[2] & (1<<7) != 0
        completionBeep = encodedData[2] & (1<<6) != 0
        programReminderInterval = TimeInterval(minutes: Double(encodedData[2] & 0x3f))
        
        units = Double(encodedData[3...].toBigEndian(UInt16.self)) / 200

        let delayCounts = encodedData[5...].toBigEndian(UInt32.self)
        timeBetweenPulses = TimeInterval(hundredthsOfMilliseconds: Double(delayCounts))

        let pulseCountX10 = encodedData[9...].toBigEndian(UInt16.self)
        squareWaveUnits = Double(pulseCountX10) / 200
        
        let intervalCounts = encodedData[5...].toBigEndian(UInt32.self)
        let timeBetweenExtendedPulses = TimeInterval(hundredthsOfMilliseconds: Double(intervalCounts))
        squareWaveDuration = timeBetweenExtendedPulses * Double(pulseCountX10) / 10
    }
    
    public init(units: Double, timeBetweenPulses: TimeInterval = Pod.secondsPerBolusPulse, squareWaveUnits: Double = 0.0, squareWaveDuration: TimeInterval = 0, acknowledgementBeep: Bool = false, completionBeep: Bool = false, programReminderInterval: TimeInterval = 0) {
        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        self.programReminderInterval = programReminderInterval
        self.units = units
        self.timeBetweenPulses = timeBetweenPulses
        self.squareWaveUnits = squareWaveUnits
        self.squareWaveDuration = squareWaveDuration
    }
}


extension BolusExtraCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "BolusExtraCommand(units:\(units), timeBetweenPulses:\(timeBetweenPulses), squareWaveUnits:\(squareWaveUnits), squareWaveDuration:\(squareWaveDuration), acknowledgementBeep:\(acknowledgementBeep), completionBeep:\(completionBeep), programReminderInterval:\(programReminderInterval.minutes))"
    }
}
