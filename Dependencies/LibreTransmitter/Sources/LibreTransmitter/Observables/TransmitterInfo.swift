//
//  TransmitterInfo.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 02/07/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import SwiftUI

public class TransmitterInfo : ObservableObject, Equatable, Hashable{
    @Published public var battery = ""
    @Published public var hardware = ""
    @Published public var firmware = ""
    @Published public var connectionState = ""
    @Published public var transmitterType = ""
    @Published public var transmitterIdentifier = "" //either mac or apple proprietary identifere
    @Published public var sensorType = ""

    public static func ==(lhs: TransmitterInfo, rhs: TransmitterInfo) -> Bool {
         lhs.battery == rhs.battery && lhs.hardware == rhs.hardware &&
         lhs.firmware == rhs.firmware && lhs.connectionState == rhs.connectionState &&
         lhs.transmitterType == rhs.transmitterType && lhs.transmitterIdentifier == rhs.transmitterIdentifier &&
         lhs.sensorType == rhs.sensorType

     }

}
