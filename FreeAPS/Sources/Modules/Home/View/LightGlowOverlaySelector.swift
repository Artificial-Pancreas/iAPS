//
//  LightGlowOverlaySelector.swift
//  FreeAPS
//
//  Created by Richard on 29.03.25.
//
import SwiftUICore

enum LightGlowOverlaySelector: String, CaseIterable, Identifiable {
    case atriumview = "Moonlight"
    case atriumview1 = "FullMoon"
    case atriumview2 = "MiddaySun"
    case atriumview3 = "EveningSun"
    case atriumview4 = "RedSun"
    case atriumview5 = "NorthernLights"

    var id: String { rawValue }

    var highlightColor: Color {
        switch self {
        case .atriumview: return Color.gray
        case .atriumview1: return Color.white
        case .atriumview2: return Color.yellow
        case .atriumview3: return Color.orange
        case .atriumview4: return Color.red
        case .atriumview5: return Color.green
        }
    }
}
