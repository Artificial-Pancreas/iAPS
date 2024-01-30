//
//  DanaKitTempBasalCalculator.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 30/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation

func absoluteBasalRateToPercentage(absoluteValue: Double, basalSchedule: [Double]) -> UInt16 {
    let now = Date()
    let startOfDay = Calendar.current.startOfDay(for: now)
    let nowTimeInterval = now.timeIntervalSince(startOfDay)
    
    let basalIntervals: [TimeInterval] = Array(0..<24).map({ TimeInterval(60 * 60 * $0) })
    let basalIndex = basalIntervals.firstIndex(where: { $0 > nowTimeInterval})! - 1
    let basalRate = basalSchedule[basalIndex]
    
    return UInt16(round(absoluteValue / basalRate * 100))
}
