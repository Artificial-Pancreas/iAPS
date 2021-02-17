//
//  CarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class CarelinkLongMessageBody: MessageBody {
    public static var length: Int = 65

    let rxData: Data

    public required init?(rxData: Data) {
        var data: Data = rxData

        if data.count < type(of: self).length {
            data.append(contentsOf: [UInt8](repeating: 0, count: type(of: self).length - data.count))
        }

        self.rxData = data
    }

    public var txData: Data {
        return rxData
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
}
