//
//  CannulaAgeOption.swift
//  FreeAPS
//
//  Created by Richard on 10.12.24.
//
enum CannulaAgeOption: String, Codable, CaseIterable {
    case Ein_Tag
    case Zwei_Tage
    case Drei_Tage
    case Vier_Tage
    case Fuenf_Tage

    var displayName: String {
        switch self {
        case .Ein_Tag: return "24"
        case .Zwei_Tage: return "48"
        case .Drei_Tage: return "72"
        case .Vier_Tage: return "96"
        case .Fuenf_Tage: return "120"
        }
    }

    var maxCannulaAge: Double {
        switch self {
        case .Ein_Tag: return 24
        case .Zwei_Tage: return 48
        case .Drei_Tage: return 72
        case .Vier_Tage: return 96
        case .Fuenf_Tage: return 120
        }
    }
}
