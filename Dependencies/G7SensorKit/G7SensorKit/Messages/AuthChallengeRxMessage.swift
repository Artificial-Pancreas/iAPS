//
//  AuthChallengeRxMessage.swift
//  xDrip5
//
//  Created by Nathan Racklyeft on 11/22/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation

struct AuthChallengeRxMessage: SensorMessage {
    let isAuthenticated: Bool
    let isBonded: Bool

    init?(data: Data) {
        guard data.count >= 3 else {
            return nil
        }

        guard data.starts(with: .authChallengeRx) else {
            return nil
        }

        isAuthenticated = data[1] == 0x1
        isBonded = data[2] == 0x1
    }
}
