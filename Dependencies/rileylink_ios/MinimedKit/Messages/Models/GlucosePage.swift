//
//  GlucosePage.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/16/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public enum GlucosePageError: Error {
    case invalidCRC
    case unknownEventType(eventType: UInt8)
}

extension GlucosePageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCRC:
            return LocalizedString("Glucose page failed crc check", comment: "Error description for glucose page failing crc check")
        case .unknownEventType(let eventType):
            return String(format: LocalizedString("Unknown glucose record type: %$1@", comment: "Format string for error description for an unknown record type in a glucose page. (1: event type number)"), eventType)
        }
    }
}


public class GlucosePage {
    
    
    public let events: [GlucoseEvent]
    public let needsTimestamp: Bool
    
    public init(pageData: Data) throws {
        
        guard checkCRC16(pageData) else {
            self.events = [GlucoseEvent]()
            throw GlucosePageError.invalidCRC
        }
        
        //glucose page parsing happens in reverse byte order because
        //opcodes are at the end of each event
        let pageData = Data(pageData.subdata(in: 0..<1022).reversed())
        
        var offset = 0
        let length = pageData.count
        var events = [GlucoseEvent]()
        let calendar = Calendar.current
        
        func matchEvent(_ offset: Int, relativeTimestamp: DateComponents) -> GlucoseEvent {
            let remainingData = pageData.subdata(in: offset..<pageData.count)
            let opcode = pageData[offset]
            if let eventType = GlucoseEventType(rawValue: opcode) {
                if let event = eventType.eventType.init(availableData: remainingData, relativeTimestamp: relativeTimestamp) {
                    return event
                }
            }
            
            if opcode >= 20 {
                return GlucoseSensorDataGlucoseEvent(availableData: remainingData, relativeTimestamp: relativeTimestamp)!
            }
            
            return UnknownGlucoseEvent(availableData: remainingData, relativeTimestamp: relativeTimestamp)!
        }
        
        
        while offset < length {
            // ignore null bytes
            if pageData[offset] == 0 {
                offset += 1
                continue
            } else {
                break
            }
        }
        
        func initialTimestamp() -> DateComponents? {
            var tempOffset = offset
            var relativeEventCount: Double = 0
            while tempOffset < length {
                let event = matchEvent(tempOffset, relativeTimestamp: DateComponents())
                if event is RelativeTimestampedGlucoseEvent {
                    relativeEventCount += 1
                } else if let sensorTimestampEvent = event as? SensorTimestampGlucoseEvent,
                    relativeEventCount == 0 || sensorTimestampEvent.isForwardOffsetReference() {
                    
                    let offsetDate = sensorTimestampEvent.timestamp.date!.addingTimeInterval(TimeInterval(minutes: relativeEventCount * 5))
                    return calendar.dateComponents([.year, .month, .day, .hour, .minute, .calendar], from: offsetDate)
                } else if !(event is NineteenSomethingGlucoseEvent /* seems to be a filler byte */ || event is DataEndGlucoseEvent) {
                    return nil
                }
                tempOffset += event.length
            }
            return nil
        }
        
        
        guard var relativeTimestamp = initialTimestamp() else {
            self.needsTimestamp = true
            self.events = events
            return
        }
        
        while offset < length {
            // ignore null bytes
            if pageData[offset] == 0 {
                offset += 1
                continue
            }
            
            let event = matchEvent(offset, relativeTimestamp: relativeTimestamp)
            if let event = event as? SensorTimestampGlucoseEvent {
                relativeTimestamp = event.timestamp
            } else if event is RelativeTimestampedGlucoseEvent {
                let offsetDate = relativeTimestamp.date!.addingTimeInterval(TimeInterval(minutes: -5))
                relativeTimestamp = calendar.dateComponents([.year, .month, .day, .hour, .minute, .calendar], from: offsetDate)
            }
            
            events.insert(event, at: 0)
            
            offset += event.length
        }
        self.needsTimestamp = false
        self.events = events
    }
}
