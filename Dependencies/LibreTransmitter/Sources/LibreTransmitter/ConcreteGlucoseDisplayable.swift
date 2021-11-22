//
//  ConcreteSensorDisplayable.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 04/11/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation
import HealthKit

public struct ConcreteGlucoseDisplayable: GlucoseDisplayable {
    public var glucoseRangeCategory: GlucoseRangeCategory?

    public var isStateValid: Bool

    public var trendType: GlucoseTrend?

    public var isLocal: Bool

    public var batteries : [(name: String, percentage: Int)]?
}

public enum GlucoseRangeCategory: Int, CaseIterable {
    case belowRange
    case urgentLow
    case low
    case normal
    case high
    case aboveRange
}

public enum GlucoseTrend: Int, CaseIterable {
    case upUpUp       = 1
    case upUp         = 2
    case up           = 3
    case flat         = 4
    case down         = 5
    case downDown     = 6
    case downDownDown = 7

    public var symbol: String {
        switch self {
        case .upUpUp:
            return "⇈"
        case .upUp:
            return "↑"
        case .up:
            return "↗︎"
        case .flat:
            return "→"
        case .down:
            return "↘︎"
        case .downDown:
            return "↓"
        case .downDownDown:
            return "⇊"
        }
    }

    public var arrows: String {
        switch self {
        case .upUpUp:
            return "↑↑"
        case .upUp:
            return "↑"
        case .up:
            return "↗︎"
        case .flat:
            return "→"
        case .down:
            return "↘︎"
        case .downDown:
            return "↓"
        case .downDownDown:
            return "↓↓"
        }
    }

    public var localizedDescription: String {
        switch self {
        case .upUpUp:
            return LocalizedString("Rising very fast", comment: "Glucose trend up-up-up")
        case .upUp:
            return LocalizedString("Rising fast", comment: "Glucose trend up-up")
        case .up:
            return LocalizedString("Rising", comment: "Glucose trend up")
        case .flat:
            return LocalizedString("Flat", comment: "Glucose trend flat")
        case .down:
            return LocalizedString("Falling", comment: "Glucose trend down")
        case .downDown:
            return LocalizedString("Falling fast", comment: "Glucose trend down-down")
        case .downDownDown:
            return LocalizedString("Falling very fast", comment: "Glucose trend down-down-down")
        }
    }
}

public protocol GlucoseDisplayable {
    /// Returns whether the current state is valid
    var isStateValid: Bool { get }

    /// Describes the state of the sensor in the current localization
    var stateDescription: String { get }

    /// Enumerates the trend of the sensor values
    var trendType: GlucoseTrend? { get }

    /// Returns whether the data is from a locally-connected device
    var isLocal: Bool { get }

    /// enumerates the glucose value type (e.g., normal, low, high)
    var glucoseRangeCategory: GlucoseRangeCategory? { get }
}


extension GlucoseDisplayable {
    public var stateDescription: String {
        if isStateValid {
            return LocalizedString("OK", comment: "Sensor state description for the valid state")
        } else {
            return LocalizedString("Needs Attention", comment: "Sensor state description for the non-valid state")
        }
    }
}
