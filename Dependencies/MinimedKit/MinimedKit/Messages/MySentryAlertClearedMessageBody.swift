//
//  MySentryAlertClearedMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


/**
Describes message sent immediately from the pump to any paired MySentry devices after a user clears an alert

See: [MinimedRF Class](https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/alert_cleared.rb)

```
a2 594040 02 80 52 14
```
*/
public struct MySentryAlertClearedMessageBody: DecodableMessageBody, DictionaryRepresentable {
    public static let length = 2

    public let alertType: MySentryAlertType?

    private let rxData: Data

    public init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        self.rxData = rxData

        alertType = MySentryAlertType(rawValue: rxData[1])
    }

    public var txData: Data {
        return rxData
    }

    public var dictionaryRepresentation: [String: Any] {
        return [
            "alertType": (alertType != nil ? String(describing: alertType!) : rxData.subdata(in: 1..<2).hexadecimalString),
            "cleared": true
        ]
    }

    public var description: String {
        return "MySentryAlertCleared(\(String(describing: alertType)))"
    }
}
