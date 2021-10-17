//
//  BasalProfile.swift
//  RileyLinkKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//


extension BasalProfile {
    var readMessageType: MessageType {
        switch self {
        case .standard:
            return .readProfileSTD512
        case .profileA:
            return .readProfileA512
        case .profileB:
            return .readProfileB512
        }
    }
}
