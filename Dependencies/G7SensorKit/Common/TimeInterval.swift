//
//  NSTimeInterval.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/9/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension TimeInterval {
    static func hours(_ hours: Double) -> TimeInterval {
        return self.init(hours: hours)
    }

    static func minutes(_ minutes: Int) -> TimeInterval {
        return self.init(minutes: Double(minutes))
    }

    static func minutes(_ minutes: Double) -> TimeInterval {
        return self.init(minutes: minutes)
    }

    static func seconds(_ seconds: Double) -> TimeInterval {
        return self.init(seconds)
    }

    static func milliseconds(_ milliseconds: Double) -> TimeInterval {
        return self.init(milliseconds / 1000)
    }

    init(minutes: Double) {
        self.init(minutes * 60)
    }

    init(hours: Double) {
        self.init(minutes: hours * 60)
    }

    init(seconds: Double) {
        self.init(seconds)
    }

    init(milliseconds: Double) {
        self.init(milliseconds / 1000)
    }

    var milliseconds: Double {
        return self * 1000
    }

    var minutes: Double {
        return self / 60.0
    }

    var hours: Double {
        return minutes / 60.0
    }
    
}
