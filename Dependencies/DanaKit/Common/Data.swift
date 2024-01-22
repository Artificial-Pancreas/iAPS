//
//  Data.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

extension Data {
    init?(hexString: String) {
      let len = hexString.count / 2
      var data = Data(capacity: len)
      var i = hexString.startIndex
      for _ in 0..<len {
        let j = hexString.index(i, offsetBy: 2)
        let bytes = hexString[i..<j]
        if var num = UInt8(bytes, radix: 16) {
          data.append(&num, count: 1)
        } else {
          return nil
        }
        i = j
      }
      self = data
    }
    
    func uint16(at index: Int) -> UInt16 {
        var value: UInt16 = 0
        (self as NSData).getBytes(&value, range: NSRange(location: index, length: MemoryLayout<UInt16>.size))
        return UInt16(littleEndian: value)
    }
    
    mutating func addDate(at index: Int, date: Date, usingUTC: Bool) {
        let calendar: Calendar = usingUTC ? .current : .autoupdatingCurrent
        
        self[index] = UInt8((calendar.component(.year, from: date) - 2000) & 0xff)
        self[index + 1] = UInt8(calendar.component(.month, from: date) & 0xff)
        self[index + 2] = UInt8(calendar.component(.day, from: date) & 0xff)
        self[index + 3] = UInt8(calendar.component(.hour, from: date) & 0xff)
        self[index + 4] = UInt8(calendar.component(.minute, from: date) & 0xff)
        self[index + 5] = UInt8(calendar.component(.second, from: date) & 0xff)
    }
    
    func date(at index: Int) -> Date {
        let year = 2000 + Int(self[startIndex])
        let month = Int(self[startIndex + 1])
        let day = Int(self[startIndex + 2])
        let hour = Int(self[startIndex + 3])
        let min = Int(self[startIndex + 4])
        let sec = Int(self[startIndex + 5])

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = min
        components.second = sec

        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
