//
//  BackgroundColorOption.swift
//  FreeAPS
//
//  Created by Richard on 05.11.24.
//
import SwiftUICore

enum BackgroundColorOption: String, CaseIterable, Identifiable, Encodable {
    case darkBlue
    case darkSlateGray4
    case teal
    case darkGreen
    case black
    case darkGray
    case snow4
    case slateGray4
    case rosyBrown4
    case indianRed4
    case burntOrange
    case autumnLeaf
    case goldenRod4
    case navajoWhite4

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .darkBlue:
            return Color(red: 0.08, green: 0.15, blue: 0.20)
        case .darkSlateGray4:
            return Color(red: 0.32, green: 0.55, blue: 0.55)
        case .teal:
            return Color(red: 0.00, green: 0.32, blue: 0.32)
        case .darkGreen:
            return Color(red: 0.10, green: 0.25, blue: 0.15)
        case .black:
            return Color(red: 0.00, green: 0.00, blue: 0.00)
        case .darkGray:
            return Color(red: 0.12, green: 0.14, blue: 0.14)
        case .snow4:
            return Color(red: 0.55, green: 0.55, blue: 0.54)
        case .slateGray4:
            return Color(red: 0.42, green: 0.48, blue: 0.55)
        case .rosyBrown4:
            return Color(red: 0.55, green: 0.41, blue: 0.41)
        case .indianRed4:
            return Color(red: 0.55, green: 0.23, blue: 0.23)
        case .burntOrange:
            return Color(red: 0.45, green: 0.22, blue: 0.12)
        case .autumnLeaf:
            return Color(red: 0.58, green: 0.33, blue: 0.09)
        case .goldenRod4:
            return Color(red: 0.55, green: 0.41, blue: 0.08)
        case .navajoWhite4:
            return Color(red: 0.55, green: 0.47, blue: 0.39)
        }
    }
}
