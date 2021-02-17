//
//  NightscoutProfileTests.swift
//  NightscoutUploadKitTests
//
//  Created by Pete Schwamb on 8/25/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import NightscoutUploadKit

class NightscoutProfileTests: XCTestCase {

    func testFixedOffsetTimezoneIdentifierConversion() {
        // This verifies that fixed offset timezones are encoded in a moment.js compatibile way
        // I.e. GMT-0500 -> "ETC/GMT+5"
        
        let timeZone = TimeZone(secondsFromGMT: -5 * 60 * 60)! // GMT-0500 (fixed)
        let isfSchedule = [ProfileSet.ScheduleItem(offset: .hours(0), value: 85)]
        let carbRatioSchedule = [ProfileSet.ScheduleItem(offset: .hours(0), value: 12)]
        let basalSchedule = [ProfileSet.ScheduleItem(offset: .hours(0), value: 1.2)]
        let targetLowSchedule = [ProfileSet.ScheduleItem(offset: .hours(0), value: 100)]
        let targetHighSchedule = [ProfileSet.ScheduleItem(offset: .hours(0), value: 110)]
        let profile = ProfileSet.Profile(timezone: timeZone, dia: .hours(6), sensitivity: isfSchedule, carbratio: carbRatioSchedule, basal: basalSchedule, targetLow: targetLowSchedule, targetHigh: targetHighSchedule, units: "mg/dL")
        
        let json = profile.dictionaryRepresentation
        
        XCTAssertEqual("ETC/GMT+5", json["timezone"] as? String)
    }

}
