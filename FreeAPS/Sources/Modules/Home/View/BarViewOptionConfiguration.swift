//
//  BarConfiguration.swift
//  FreeAPS
//
//  Created by Richard on 03.02.25.
//
enum BarViewOptionConfiguration: String, CaseIterable {
    case none = "bars_none"
    case top = "bars_top"
    case dana = "bars_dana"
    case tt = "bars_tt"
    case bottom = "bars_bottom"
    case topDana = "bars_top_dana"
    case topTT = "bars_top_tt"
    case topBottom = "bars_top_bottom"
    case danaTT = "bars_dana_tt"
    case danaBottom = "bars_dana_bottom"
    case ttBottom = "bars_tt_bottom"
    case topDanaTT = "bars_top_dana_tt"
    case topDanaBottom = "bars_top_dana_bottom"
    case topTTBottom = "bars_top_tt_bottom"
    case danaTTBottom = "bars_dana_tt_bottom"
    case all = "bars_top_dana_tt_bottom"

    var imageName: String { rawValue }
}
