//
//  GlucoseRxMessage.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit


extension Glucose: GlucoseDisplayable {
    public var isStateValid: Bool {
        return state == .known(.ok) && status == .ok
    }

    public var stateDescription: String {
        var messages = [String]()

        switch state {
        case .known(.ok):
            break  // Suppress the "OK" message
        default:
            messages.append(state.localizedDescription)
        }

        switch self.status {
        case .ok:
            if messages.isEmpty {
                messages.append(status.localizedDescription)
            } else {
                break  // Suppress the "OK" message
            }
        case .lowBattery, .unknown:
            messages.append(status.localizedDescription)
        }

        return messages.joined(separator: ". ")
    }

    public var trendType: GlucoseTrend? {
        guard trend < Int(Int8.max) else {
            return nil
        }

        switch trend {
        case let x where x <= -30:
            return .downDownDown
        case let x where x <= -20:
            return .downDown
        case let x where x <= -10:
            return .down
        case let x where x < 10:
            return .flat
        case let x where x < 20:
            return .up
        case let x where x < 30:
            return .upUp
        default:
            return .upUpUp
        }
    }

    public var isLocal: Bool {
        return true
    }
    
    // TODO Placeholders. This functionality will come with LOOP-1311
    public var glucoseRangeCategory: GlucoseRangeCategory? {
        return nil
    }
}

extension Glucose {
    public var condition: GlucoseCondition? {
        if glucoseMessage.glucose < GlucoseLimits.minimum {
            return .belowRange
        } else if glucoseMessage.glucose > GlucoseLimits.maximum {
            return .aboveRange
        } else {
            return nil
        }
    }
}
