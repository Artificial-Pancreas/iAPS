//
//  NumberFormatter.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 15/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation

extension NumberFormatter {
    func string(from number: Double) -> String? {
        return string(from: NSNumber(value: number))
    }
}
