//
//  PumpRegion.swift
//  RileyLink
//
//  Created by Pete Schwamb on 9/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public enum PumpRegion: Int, CustomStringConvertible  {
    case northAmerica = 0
    case worldWide
    case canada
    
    public var description: String {
        switch self {
        case .worldWide:
            return LocalizedString("World-Wide", comment: "Describing the worldwide pump region")
        case .northAmerica:
            return LocalizedString("North America", comment: "Describing the North America pump region")
        case .canada:
            return LocalizedString("Canada", comment: "Describing the Canada pump region ")
        }
    }
}
