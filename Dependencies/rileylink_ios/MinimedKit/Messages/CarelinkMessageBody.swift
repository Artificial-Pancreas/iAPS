//
//  CarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation

extension Data {
    func paddedTo(length: Int) -> Data {
        var data = self
        data.append(contentsOf: [UInt8](repeating: 0, count: length - data.count))
        return data
    }
}

public class CarelinkLongMessageBody: DecodableMessageBody {
    public static var length: Int = 65

    let rxData: Data

    public required init?(rxData: Data) {
        self.rxData = rxData.paddedTo(length: type(of: self).length)
    }

    public var txData: Data {
        return rxData
    }

    public var description: String {
        return "CarelinkLongMessage(\(rxData.hexadecimalString))"
    }

}


public class CarelinkShortMessageBody: MessageBody {
    public static var length: Int = 1

    let data: Data

    public convenience init() {
        self.init(rxData: Data(repeating: 0, count: 1))!
    }

    public required init?(rxData: Data) {
        self.data = rxData

        if rxData.count != type(of: self).length {
            return nil
        }
    }

    public var txData: Data {
        return data
    }

    public var description: String {
        return "CarelinkShortMessage(\(data.hexadecimalString))"
    }

}
