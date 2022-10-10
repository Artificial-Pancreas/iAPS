//
//  MySentryAlertMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


/**
Describes an alert message sent immediately from the pump to any paired MySentry devices

See: [MinimedRF Class](https://github.com/ps2/minimed_rf/blob/master/lib/minimed_rf/messages/alert.rb)

```
a2 594040 01 7c 65 0727070f0906 0175 4c
```
*/
public struct MySentryAlertMessageBody: DecodableMessageBody, DictionaryRepresentable {
    public static let length = 10

    public let alertType: MySentryAlertType?
    public let alertDate: Date

    private let rxData: Data

    public init?(rxData: Data) {
        guard rxData.count == type(of: self).length, let
            alertDate = DateComponents(mySentryBytes: rxData.subdata(in: 2..<8)).date
        else {
            return nil
        }

        self.rxData = rxData

        alertType = MySentryAlertType(rawValue: rxData[1])
        self.alertDate = alertDate
    }

    public var txData: Data {
        return rxData
    }

    public var dictionaryRepresentation: [String: Any] {
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        return [
            "alertDate": dateFormatter.string(from: alertDate),
            "alertType": (alertType != nil ? String(describing: alertType!) : rxData.subdata(in: 1..<2).hexadecimalString),
            "byte89": rxData.subdata(in: 8..<10).hexadecimalString
        ]
    }

    public var description: String {
        return "MySentryAlert(\(String(describing: alertType)), \(alertDate))"
    }

}
