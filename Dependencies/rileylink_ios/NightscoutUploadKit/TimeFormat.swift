//
//  TimeFormat.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

class TimeFormat: NSObject {
    private static var formatterISO8601 = DateFormatter.ISO8601DateFormatter()
    
    static func timestampStrFromDate(_ date: Date) -> String {
        return formatterISO8601.string(from: date)
    }
}
