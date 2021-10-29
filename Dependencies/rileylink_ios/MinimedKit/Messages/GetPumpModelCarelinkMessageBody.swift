//
//  GetPumpModelCarelinkMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/12/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class GetPumpModelCarelinkMessageBody: CarelinkLongMessageBody {
    public let model: String
    
    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length,
            let mdl = String(data: rxData.subdata(in: 2..<5), encoding: String.Encoding.ascii) else {
                model = ""
                super.init(rxData: rxData)
                return nil
        }
        model = mdl
        super.init(rxData: rxData)
    }

    public required init?(rxData: NSData) {
        fatalError("init(rxData:) has not been implemented")
    }
}
