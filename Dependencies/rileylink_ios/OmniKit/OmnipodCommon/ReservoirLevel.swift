//
//  ReservoirLevel.swift
//  OmniKit
//
//  Created by Pete Schwamb on 5/31/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

public enum ReservoirLevel: RawRepresentable, Equatable {
    public typealias RawValue = Double

    case valid(Double)
    case aboveThreshold

    public var percentage: Double {
        switch self {
        case .aboveThreshold:
            return 1
        case .valid(let value):
            // Set 50U as the halfway mark, even though pods can hold 200U.
            return min(1, max(0, value / 100))
        }
    }

    public init(rawValue: RawValue) {
        if rawValue > Pod.maximumReservoirReading {
            self = .aboveThreshold
        } else {
            self = .valid(rawValue)
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .valid(let value):
            return value
        case .aboveThreshold:
            return Pod.reservoirLevelAboveThresholdMagicNumber
        }
    }
}
