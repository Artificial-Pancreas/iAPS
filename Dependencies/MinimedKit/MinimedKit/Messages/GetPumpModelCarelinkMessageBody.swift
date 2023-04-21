//
//  GetPumpModelCarelinkMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/12/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public class GetPumpModelCarelinkMessageBody: DecodableMessageBody {
    public var txData: Data

    public static var length: Int = 65

    public let model: String
    
    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length,
            let mdl = String(data: rxData.subdata(in: 2..<5), encoding: String.Encoding.ascii) else {
                model = ""
                return nil
        }
        model = mdl
        txData = rxData
    }

    public var description: String {
        return "GetPumpModel(\(model))"
    }

}
