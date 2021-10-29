//
//  PumpMessage.swift
//  RileyLinkKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//


extension PumpMessage {
    /// Initializes a Carelink message using settings and a default body
    ///
    /// - Parameters:
    ///   - settings: Pump settings used for determining address
    ///   - type: The message type
    ///   - body: The message body, defaulting to a 1-byte empty body
    init(settings: PumpSettings, type: MessageType, body: MessageBody = CarelinkShortMessageBody()) {
        self.init(packetType: .carelink, address: settings.pumpID, messageType: type, messageBody: body)
    }
}
