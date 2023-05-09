//
//  ReadCurrentGlucosePageMessageBody.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/19/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public class ReadCurrentGlucosePageMessageBody: CarelinkLongMessageBody {
    
    public let pageNum: UInt32
    public let glucose: Int
    public let isig: Int
    
    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        self.pageNum = rxData[1..<5
            ].toBigEndian(UInt32.self)
        self.glucose = Int(rxData[6])
        self.isig = Int(rxData[8])
        
        super.init(rxData: rxData)
    }
}
