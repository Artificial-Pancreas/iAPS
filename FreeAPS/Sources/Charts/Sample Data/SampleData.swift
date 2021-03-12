//
//  SampleData.swift
//  FreeAPSCharts
//
//  Created by Яков Карпов on 08.03.2021.
//

import Foundation

enum SampleData {
    
    static private var baseComponents: DateComponents = {
        var dateComponents = DateComponents()
        dateComponents.year = 2021
        dateComponents.month = 3
        dateComponents.day = 8
        dateComponents.timeZone = TimeZone(abbreviation: "MSK")
        dateComponents.hour = 8
        return dateComponents
    }()
    
    static private func generateDate(baseDateComponents: DateComponents, minutes: Int) -> Date {
        var localComponents = baseDateComponents
        localComponents.minute = minutes
        let userCalendar = Calendar(identifier: .gregorian)
        return userCalendar.date(from: localComponents)!
    }
    
    static private func generateGlucoseStream(startingPoint: Int, length: Int, amount: Int, direction: Int) -> [Int] {
        
        // Downwards
        if direction == 0 {
            return (1 ... length).map { startingPoint - $0 * amount }
        }
        return (1 ... length).map { startingPoint + $0 * amount }
    }
    
    static var sampleData: [BloodGlucose] {
        let mediumUp = generateGlucoseStream(startingPoint: 77, length: 80, amount: 2, direction: 1)
        let fastUp = generateGlucoseStream(startingPoint: mediumUp.last!, length: 20, amount: 5, direction: 1)
        let fastDown = generateGlucoseStream(startingPoint: fastUp.last!, length: 12, amount: 13, direction: 0)
        let mediumDown = generateGlucoseStream(startingPoint: fastDown.last!, length: 33, amount: 3, direction: 0)
        let slowUp = generateGlucoseStream(startingPoint: mediumDown.last!, length: 144, amount: 1, direction: 1)
        
        let glucose = mediumUp + fastUp + fastDown + mediumDown + slowUp
        let normalTime = (0 ... 278).map{ generateDate(baseDateComponents: baseComponents, minutes: $0 * 5) }
        let tenMinutes = (279 ... 288).map{ generateDate(baseDateComponents: baseComponents, minutes: $0 * 30) }
        let time = normalTime + tenMinutes
        
        
        return zip(glucose, time).map { BloodGlucose(sgv: $0, direction: nil, date: UInt64($1.timeIntervalSince1970), dateString: $1, filtered: nil, noise: nil, glucose: nil) }
    }
}
