//
//  ISO8601DateFormatter.swift
//  RileyLink
//
//  Created by Nate Racklyeft on 6/15/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation


extension ISO8601DateFormatter {

    class func defaultFormatter() -> Self {
        let formatter = self.init()
        formatter.formatOptions = .withInternetDateTime //Ex: 2023-01-09T20:44:28Z
        
        return formatter
    }
    
    class func fractionalSecondsFormatter() -> Self {
        let formatter = self.init()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] //Ex: 2023-01-09T20:44:28.253Z

        return formatter
    }
}
