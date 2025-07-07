//
//  InsulinAgeOption.swift
//  FreeAPS
//
//  Created by Richard on 10.12.24.
//
enum InsulinAgeOption: String, Codable, CaseIterable {
    case Ein_Tag
    case Zwei_Tage
    case Drei_Tage
    case Vier_Tage
    case Fuenf_Tage
    case Sechs_Tage
    case Sieben_Tage
    case Acht_Tage
    case Neun_Tage
    case Zehn_Tage

    var displayName: String {
        switch self {
        case .Ein_Tag: return "24"
        case .Zwei_Tage: return "48"
        case .Drei_Tage: return "72"
        case .Vier_Tage: return "96"
        case .Fuenf_Tage: return "120"
        case .Sechs_Tage: return "144"
        case .Sieben_Tage: return "168"
        case .Acht_Tage: return "192"
        case .Neun_Tage: return "216"
        case .Zehn_Tage: return "240"
        }
    }

    var maxInsulinAge: Double {
        switch self {
        case .Ein_Tag: return 24
        case .Zwei_Tage: return 48
        case .Drei_Tage: return 72
        case .Vier_Tage: return 96
        case .Fuenf_Tage: return 120
        case .Sechs_Tage: return 144
        case .Sieben_Tage: return 168
        case .Acht_Tage: return 192
        case .Neun_Tage: return 216
        case .Zehn_Tage: return 240
        }
    }
}
