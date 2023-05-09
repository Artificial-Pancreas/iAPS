//
//  BolusCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class BolusCarelinkMessageBody: CarelinkLongMessageBody {
    
    public convenience init(units: Double, insulinBitPackingScale: Int = 10) {
        
        let length: Int
        let scrollRate: Int
        
        if insulinBitPackingScale >= 40 {
            length = 2
            
            // 40-stroke pumps scroll faster for higher unit values
            switch units {
            case let u where u > 10:
                scrollRate = 4
            case let u where u > 1:
                scrollRate = 2
            default:
                scrollRate = 1
            }
        } else {
            length = 1
            scrollRate = 1
        }
        
        let strokes = Int(units * Double(insulinBitPackingScale / scrollRate)) * scrollRate
        
        let data = Data(hexadecimalString: String(format: "%02x%0\(2 * length)x", length, strokes))!
        
        self.init(rxData: data)!
    }
    
}
