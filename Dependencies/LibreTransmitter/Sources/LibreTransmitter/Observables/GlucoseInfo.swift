//
//  GlucoseInfo.swift
//  LibreTransmitter
//
//  Created by Bjørn Inge Berg on 02/07/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import Foundation

public class GlucoseInfo : ObservableObject, Equatable, Hashable{

    @Published public var glucose = "" //dynamic based users preference
    @Published public var glucoseMMOL = ""
    @Published public var glucoseMGDL = ""
    @Published public var date = ""
    @Published public var checksum = ""
    //@Published var entryErrors = ""

    @Published public var prediction = ""
    @Published public var predictionMMOL = ""
    @Published public var predictionMGDL = ""
    @Published public var predictionDate = ""

    public static func ==(lhs: GlucoseInfo, rhs: GlucoseInfo) -> Bool {
         lhs.glucose == rhs.glucose && lhs.date == rhs.date &&
         lhs.checksum == rhs.checksum && lhs.prediction == rhs.prediction && lhs.predictionDate == rhs.predictionDate

     }
}
