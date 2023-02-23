//
//  InsulinDataSource.swift
//  Loop
//
//  Created by Nathan Racklyeft on 6/10/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum InsulinDataSource: Int, CustomStringConvertible, CaseIterable {
    case pumpHistory = 0
    case reservoir

    public var description: String {
        switch self {
        case .pumpHistory:
            return LocalizedString("Event History", comment: "Describing the pump history insulin data source")
        case .reservoir:
            return LocalizedString("Reservoir", comment: "Describing the reservoir insulin data source")
        }
    }
}
