//
//  AlarmStatus.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 09/07/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import Foundation
public class AlarmStatus : ObservableObject , Equatable, Hashable{
    @Published public var isAlarming = false
    @Published public var glucoseScheduleAlarmResult = GlucoseScheduleAlarmResult.none

    public static func ==(lhs: AlarmStatus, rhs: AlarmStatus) -> Bool {
         lhs.isAlarming == rhs.isAlarming && lhs.glucoseScheduleAlarmResult == rhs.glucoseScheduleAlarmResult
    }

    static public func createNew() -> AlarmStatus{
        AlarmStatus()
    }
}
