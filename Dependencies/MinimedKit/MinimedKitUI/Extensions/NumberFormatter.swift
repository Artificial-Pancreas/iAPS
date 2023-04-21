//
//  NumberFormatter.swift
//  MinimedKitUI
//
//  Created by Pete Schwamb on 3/19/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation

extension NumberFormatter {

    func decibleString(from decibles: Int?) -> String? {
        if let decibles = decibles, let formatted = string(from: NSNumber(value: decibles)) {
            return String(format: LocalizedString("%@ dB", comment: "Unit format string for an RSSI value in decibles"), formatted)
        } else {
            return nil
        }
    }

    func string(from number: Double) -> String? {
        return string(from: NSNumber(value: number))
    }

    func string(from number: Double, unit: String, style: Formatter.UnitStyle = .medium, avoidLineBreaking: Bool = true) -> String? {
        guard let stringValue = string(from: number) else {
            return nil
        }

        let separator: String
        switch style {
        case .long:
            separator = " "
        case .medium:
            separator = avoidLineBreaking ? .nonBreakingSpace : " "
        case .short:
            fallthrough
        @unknown default:
            separator = avoidLineBreaking ? .wordJoiner : ""
        }

        let unit = avoidLineBreaking ? unit.replacingOccurrences(of: "/", with: "\(String.wordJoiner)/\(String.wordJoiner)") : unit

        return String(
            format: LocalizedString("%1$@%2$@%3$@", comment: "String format for value with units (1: value, 2: separator, 3: units)"),
            stringValue,
            separator,
            unit
        )
    }
}

public extension String {
    static let nonBreakingSpace = "\u{00a0}"
    static let wordJoiner = "\u{2060}"
}
