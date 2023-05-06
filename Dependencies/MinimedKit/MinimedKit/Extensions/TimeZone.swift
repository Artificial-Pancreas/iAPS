//
//  TimeZone.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 3/19/23.
//

import Foundation

extension TimeZone {
    static var currentFixed: TimeZone {
        return TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT())!
    }

    var fixed: TimeZone {
        return TimeZone(secondsFromGMT: secondsFromGMT())!
    }
}
