//
//  StatusResponse.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/23/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public struct StatusResponse : MessageBlock {
    public let blockType: MessageBlockType = .statusResponse
    public let length: UInt8 = 10
    public let deliveryStatus: DeliveryStatus
    public let podProgressStatus: PodProgressStatus
    public let timeActive: TimeInterval
    public let reservoirLevel: Double?
    public let insulin: Double
    public let bolusNotDelivered: Double
    public let podMessageCounter: UInt8
    public let alerts: AlertSet
    
    
    public let data: Data
    
    public init(encodedData: Data) throws {
        if encodedData.count < length {
            throw MessageBlockError.notEnoughData
        }
        
        data = encodedData.prefix(upTo: Int(length))
        
        guard let deliveryStatus = DeliveryStatus(rawValue: encodedData[1] >> 4) else {
            throw MessageError.unknownValue(value: encodedData[1] >> 4, typeDescription: "DeliveryStatus")
        }
        self.deliveryStatus = deliveryStatus
        
        guard let podProgressStatus = PodProgressStatus(rawValue: encodedData[1] & 0xf) else {
            throw MessageError.unknownValue(value: encodedData[1] & 0xf, typeDescription: "PodProgressStatus")
        }
        self.podProgressStatus = podProgressStatus

        let minutes = ((Int(encodedData[7]) & 0x7f) << 6) + (Int(encodedData[8]) >> 2)
        self.timeActive = TimeInterval(minutes: Double(minutes))
        
        let highInsulinBits = Int(encodedData[2] & 0xf) << 9
        let midInsulinBits = Int(encodedData[3]) << 1
        let lowInsulinBits = Int(encodedData[4] >> 7)
        self.insulin = Double(highInsulinBits | midInsulinBits | lowInsulinBits) / Pod.pulsesPerUnit
        
        self.podMessageCounter = (encodedData[4] >> 3) & 0xf
        
        self.bolusNotDelivered = Double((Int(encodedData[4] & 0x3) << 8) | Int(encodedData[5])) / Pod.pulsesPerUnit

        self.alerts = AlertSet(rawValue: ((encodedData[6] & 0x7f) << 1) | (encodedData[7] >> 7))
        
        let reservoirValue = Double((Int(encodedData[8] & 0x3) << 8) + Int(encodedData[9])) / Pod.pulsesPerUnit
        if reservoirValue <= Pod.maximumReservoirReading {
                self.reservoirLevel = reservoirValue
        } else {
            self.reservoirLevel = nil
        }
    }
}

extension StatusResponse: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "StatusResponse(deliveryStatus:\(deliveryStatus), progressStatus:\(podProgressStatus), timeActive:\(timeActive.stringValue), reservoirLevel:\(String(describing: reservoirLevel)), delivered:\(insulin), bolusNotDelivered:\(bolusNotDelivered), seq:\(podMessageCounter), alerts:\(alerts))"
    }
}

