//
//  SensorInfo.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 02/07/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import Foundation
public class SensorInfo : ObservableObject, Equatable, Hashable{
    @Published public var sensorAge = ""
    @Published public var sensorAgeLeft = ""
    @Published public var sensorEndTime = ""
    @Published public var sensorState = ""
    @Published public var sensorSerial = ""

    public static func ==(lhs: SensorInfo, rhs: SensorInfo) -> Bool {
         lhs.sensorAge == rhs.sensorAge && lhs.sensorAgeLeft == rhs.sensorAgeLeft &&
         lhs.sensorEndTime == rhs.sensorEndTime && lhs.sensorState == rhs.sensorState &&
         lhs.sensorSerial == rhs.sensorSerial

     }

}
