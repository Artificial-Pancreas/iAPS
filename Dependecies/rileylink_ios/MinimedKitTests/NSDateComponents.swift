//
//  NSDateComponents.swift
//  RileyLink
//
//  Created by Nathan Racklyeft on 4/9/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation


extension DateComponents {
    
    init(gregorianYear year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
        self.init()
        
        self.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }
    
}
